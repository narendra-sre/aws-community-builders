data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"
  source_arn  = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Purpose   = "VPC Flow Logs and Athena"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid    = "FlowLogsAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.source_arn]
    }
  }

  statement {
    sid    = "FlowLogsWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.source_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_flow_log" "vpc" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.logs.arn

  depends_on = [aws_s3_bucket_policy.logs]

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_athena_workgroup" "logs" {
  name = "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.logs.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

resource "aws_athena_named_query" "create_table" {
  name        = "${var.project_name}-create-table"
  description = "Create Athena table for VPC Flow Logs."
  workgroup   = aws_athena_workgroup.logs.id
  database    = "default"

  query = <<-SQL
    CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
      version int,
      account_id string,
      interface_id string,
      srcaddr string,
      dstaddr string,
      srcport int,
      dstport int,
      protocol bigint,
      packets bigint,
      bytes bigint,
      start_time bigint,
      end_time bigint,
      action string,
      log_status string
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ' '
    STORED AS TEXTFILE
    LOCATION 's3://${aws_s3_bucket.logs.bucket}/AWSLogs/';
  SQL
}
