#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 sql-file"; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$1"; [[ "$FILE" = /* ]] || FILE="$ROOT/$FILE"
[[ -f "$FILE" ]] || { echo "SQL file not found: $FILE"; exit 2; }
REGION="$(awk -F '"' '/aws_region/ {print $2}' "$ROOT/terraform/terraform.tfvars")"
WG="$(terraform -chdir="$ROOT/terraform" output -raw athena_workgroup_name)"
BUCKET="$(terraform -chdir="$ROOT/terraform" output -raw flow_logs_bucket_name)"
SQL="$(cat "$FILE")"; SQL="${SQL//__FLOW_LOGS_BUCKET__/$BUCKET}"
QID="$(aws athena start-query-execution --region "$REGION" --work-group "$WG" --query-execution-context Database=default --query-string "$SQL" --query 'QueryExecutionId' --output text)"
echo "Query ID: $QID"
for i in $(seq 1 120); do
  STATE="$(aws athena get-query-execution --region "$REGION" --query-execution-id "$QID" --query 'QueryExecution.Status.State' --output text)"
  echo "State: $STATE"
  case "$STATE" in
    SUCCEEDED) break ;;
    FAILED|CANCELLED) aws athena get-query-execution --region "$REGION" --query-execution-id "$QID" --query 'QueryExecution.Status' --output json; exit 1 ;;
  esac
  sleep 5
done
[[ "$STATE" == "SUCCEEDED" ]] || { echo "Timed out; check Athena console."; exit 1; }
aws athena get-query-results --region "$REGION" --query-execution-id "$QID" --output table
aws athena get-query-execution --region "$REGION" --query-execution-id "$QID" --query 'QueryExecution.ResultConfiguration.OutputLocation' --output text
