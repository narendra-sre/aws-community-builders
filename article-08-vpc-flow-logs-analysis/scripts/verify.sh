#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="$(awk -F '"' '/aws_region/ {print $2}' "$ROOT/terraform/terraform.tfvars")"
BUCKET="$(terraform -chdir="$ROOT/terraform" output -raw flow_logs_bucket_name)"
WG="$(terraform -chdir="$ROOT/terraform" output -raw athena_workgroup_name)"
echo "== Flow Logs =="
aws ec2 describe-flow-logs --region "$REGION" --query 'FlowLogs[].{Id:FlowLogId,Status:FlowLogStatus,Traffic:TrafficType,VPC:ResourceId,Error:DeliverLogsErrorMessage}' --output table
echo "== S3 security =="
aws s3api get-public-access-block --bucket "$BUCKET" --region "$REGION"
aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION"
echo "== Athena workgroup =="
aws athena get-work-group --work-group "$WG" --region "$REGION" --query 'WorkGroup.{Name:Name,State:State,Output:Configuration.ResultConfiguration.OutputLocation}' --output table
echo "== Delivered files (may be empty initially) =="
aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive | head -30 || true
