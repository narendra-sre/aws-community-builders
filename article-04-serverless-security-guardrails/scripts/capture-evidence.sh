#!/usr/bin/env bash
# Saves sanitized outputs into evidence/ so the article can reference them.
# Account IDs are replaced with a placeholder before anything is written.
set -euo pipefail

REGION="${AWS_REGION:-ap-south-2}"
EVIDENCE_DIR="$(cd "$(dirname "$0")/.." && pwd)/evidence"
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)/terraform"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
mkdir -p "$EVIDENCE_DIR"

sanitize() {
  sed -e "s/${ACCOUNT_ID}/111122223333/g"
}

echo "== Terraform plan summary"
( cd "$TF_DIR" && terraform show -json tfplan 2>/dev/null ) | sanitize \
  > "$EVIDENCE_DIR/terraform-plan-summary.json" || echo "   (run 'terraform plan -out=tfplan' first)"

echo "== Guardrail findings table"
aws dynamodb scan --region "$REGION" \
  --table-name "$(cd "$TF_DIR" && terraform output -raw findings_table_name)" \
  --output json | sanitize > "$EVIDENCE/findings-table-sanitized.json"

echo "== Remediator logs (last 30 minutes)"
START_MS=$(( ($(date +%s) - 1800) * 1000 ))
aws logs filter-log-events --region "$REGION" \
  --log-group-name "/aws/lambda/$(cd "$TF_DIR" && terraform output -raw remediator_function_name)" \
  --start-time "$START_MS" --output json | sanitize > "$EVIDENCE/remediator-logs-sanitized.json"

echo "== CloudTrail events for the test actions"
aws cloudtrail lookup-events --region "$REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress \
  --max-results 10 --output json | sanitize > "$EVIDENCE/cloudtrail-authorize-ingress-sanitized.json"
aws cloudtrail lookup-events --region "$REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteBucketPublicAccessBlock \
  --max-results 10 --output json | sanitize > "$EVIDENCE/cloudtrail-delete-public-access-block-sanitized.json"

echo "== Security group state after remediation"
if [ -f "$(dirname "$0")/../.last_test_sg" ]; then
  aws ec2 describe-security-groups --region "$REGION" \
    --group-ids "$(cat "$(dirname "$0")/../.last_test_sg")" --output json | sanitize \
    > "$EVIDENCE/sg-after-remediation-sanitized.json"
fi

echo "Evidence written to $EVIDENCE_DIR"
echo "Now add screenshots to evidence/screenshots/ and check every file for leaked identifiers before committing."
