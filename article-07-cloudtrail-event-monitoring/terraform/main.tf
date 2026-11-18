resource "random_id" "suffix" {
  byte_length = 3
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_sns_topic" "security_group_alerts" {
  name = "${var.name_prefix}-${random_id.suffix.hex}"
}

data "aws_iam_policy_document" "sns_topic" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_group_alerts.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.security_group_changes.arn]
    }
  }
}

resource "aws_sns_topic_policy" "security_group_alerts" {
  arn    = aws_sns_topic.security_group_alerts.arn
  policy = data.aws_iam_policy_document.sns_topic.json
}

resource "aws_cloudwatch_event_rule" "security_group_changes" {
  name        = "${var.name_prefix}-${random_id.suffix.hex}"
  description = "Detect selected EC2 security group rule changes from CloudTrail."
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName = [
        "AuthorizeSecurityGroupIngress",
        "RevokeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
        "RevokeSecurityGroupEgress"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "notify_sns" {
  rule      = aws_cloudwatch_event_rule.security_group_changes.name
  target_id = "SendSecurityGroupChangeToSNS"
  arn       = aws_sns_topic.security_group_alerts.arn
  depends_on = [aws_sns_topic_policy.security_group_alerts]
}

resource "aws_security_group" "test" {
  name        = "${var.name_prefix}-test-${random_id.suffix.hex}"
  description = "Dedicated test security group for EventBridge alert demonstration."
  vpc_id      = data.aws_vpc.default.id
  # No ingress or egress rules are opened by this configuration.
}
