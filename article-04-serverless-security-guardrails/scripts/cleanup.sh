#!/usr/bin/env bash
# Removes test resources created by simulate-violations.sh, then destroys the Terraform stack.
set -euo pipefail

REGION="${AWS_REGION:-ap-south-2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "== Removing test security groups"
for sg in "$(cat "$ROOT_DIR/.last_test_sg" 2>/dev/null || true)" "$(cat "$ROOT_DIR/.last_test_sg_exempt" 2>/dev/null || true)"; do
  if [ -n "$sg" ]; then
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null && echo "   deleted $sg" || echo "   $sg already gone"
  fi
done
rm -f "$ROOT_DIR/.last_test_sg" "$ROOT_DIR/.last_test_sg_exempt"

echo "== Removing test buckets (guardrail-test-*)"
for bucket in $(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'guardrail-test-')].Name" --output text); do
  aws s3 rb "s3://$bucket" --force --region "$REGION" && echo "   deleted $bucket"
done

echo "== Destroying Terraform stack"
( cd "$ROOT_DIR/terraform" && terraform destroy -auto-approve )
echo "Cleanup complete."
