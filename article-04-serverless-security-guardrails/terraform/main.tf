data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  lambda_name = "${var.project_name}-remediator"
  bucket_events = [
    "PutBucketPublicAccessBlock",
    "DeleteBucketPublicAccessBlock",
  ]
}

# ---------------------------------------------------------------------------
# Audit store, alerting, and failure queue
# ---------------------------------------------------------------------------

# One item per EventBridge event, keyed by event ID. A conditional PutItem on
# this key makes processing idempotent: each event is handled at most once.
resource "aws_dynamodb_table" "findings" {
  name         = "${var.project_name}-findings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Events that fail every retry land here so nothing is silently dropped.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowViolationRuleToSendFailedEvents"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.violations.arn }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Remediator Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "remediator" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14 # keeps log storage cost inside the free tier
}

resource "aws_iam_role" "remediator" {
  name = "${var.project_name}-remediator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least privilege: each statement grants only what the handler calls.
resource "aws_iam_role_policy" "remediator" {
  name = "${var.project_name}-remediator"
  role = aws_iam_role.remediator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.lambda_name}:*"
      },
      {
        # Describe actions do not support resource-level permissions.
        Sid      = "DescribeSecurityGroups"
        Effect   = "Allow"
        Action   = ["ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
      {
        Sid      = "RevokeSecurityGroupRules"
        Effect   = "Allow"
        Action   = ["ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:${var.aws_region}:${local.account_id}:security-group/*"
      },
      {
        # Known gap: scoped to all buckets. Narrowing with a tag condition is listed as future work.
        Sid    = "ManageS3PublicAccessBlock"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid      = "RecordFindings"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.findings.arn
      },
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
    ]
  })
}

data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/.build/handler.zip"
}

resource "aws_lambda_function" "remediator" {
  function_name    = local.lambda_name
  role             = aws_iam_role.remediator.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      FINDINGS_TABLE  = aws_dynamodb_table.findings.name
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
      DRY_RUN         = tostring(var.dry_run)
      SENSITIVE_PORTS = var.sensitive_ports
      EXEMPT_TAG_KEY  = var.exempt_tag_key
    }
  }

  depends_on = [aws_cloudwatch_log_group.remediator]
}

# ---------------------------------------------------------------------------
# Detection: EventBridge rule on CloudTrail management events
# ---------------------------------------------------------------------------

# CloudTrail management events reach the default event bus as
# "AWS API Call via CloudTrail", so no extra trail is required for detection.
resource "aws_cloudwatch_event_rule" "violations" {
  name        = "${var.project_name}-violations"
  description = "CloudTrail API calls that open sensitive ports or weaken S3 public access blocks"

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com", "s3.amazonaws.com"]
      eventName   = concat(["AuthorizeSecurityGroupIngress"], local.bucket_events)
    }
  })
}

resource "aws_cloudwatch_event_target" "remediator" {
  rule      = aws_cloudwatch_event_rule.violations.name
  target_id = "remediator"
  arn       = aws_lambda_function.remediator.arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowViolationRuleInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.violations.arn
}
