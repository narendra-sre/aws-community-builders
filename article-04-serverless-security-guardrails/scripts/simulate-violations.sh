#!/usr/bin/env bash
# Triggers the three scenarios the guardrail must handle:
#   1. SSH open to 0.0.0.0/0 on an untagged security group     -> violation
#   2. SSH open to 0.0.0.0/0 on a security group tagged exempt  -> allowed
#   3. Public access block deleted on a bucket                   -> violation
# Uses the default VPC and creates only free-tier-friendly resources.
set -euo pipefail

REGION="${AWS_REGION:-ap-south-2}"
RUN_ID="$(date +%s)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" \
  --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"

echo "== Scenario 1: open SSH on an untagged security group"
SG_ID="$(aws ec2 create-security-group --region "$REGION" \
  --group-name "guardrail-test-$RUN_ID" --description "guardrail violation test" \
  --vpc-id "$VPC_ID" --query GroupId --output text)"
echo "$SG_ID" > .last_test_sg
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
echo "   created $SG_ID and authorized 0.0.0.0/0 on tcp/22"

echo "== Scenario 2: open SSH on an exempt security group"
EXEMPT_SG_ID="$(aws ec2 create-security-group --region "$REGION" \
  --group-name "guardrail-test-exempt-$RUN_ID" --description "guardrail exemption test" \
  --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=guardrail-exempt,Value=true}]' \
  --query GroupId --output text)"
echo "$EXEMPT_SG_ID" > .last_test_sg_exempt
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$EXEMPT_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
echo "   created exempt $EXEMPT_SG_ID and authorized 0.0.0.0/0 on tcp/22"

echo "== Scenario 3: remove the public access block from a bucket"
BUCKET="guardrail-test-${RUN_ID}-${ACCOUNT_ID}"
aws s3api create-bucket --region "$REGION" --bucket "$BUCKET" \
  --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
aws s3api delete-public-access-block --region "$REGION" --bucket "$BUCKET"
echo "   created $BUCKET and deleted its public access block"

echo "== Waiting 60 seconds for EventBridge and Lambda to react"
sleep 60

echo "== Results"
echo "-- Scenario 1 ingress rules (expected: 0.0.0.0/0 removed in enforce mode):"
aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions' --output json
echo "-- Scenario 2 ingress rules (expected: 0.0.0.0/0 still present, exempt):"
aws ec2 describe-security-groups --region "$REGION" --group-ids "$EXEMPT_SG_ID" \
  --query 'SecurityGroups[0].IpPermissions' --output json
echo "-- Scenario 3 public access block (expected: all four settings true):"
aws s3api get-public-access-block --region "$REGION" --bucket "$BUCKET" --output json || \
  echo "   no public access block configured (guardrail did not act yet, or is in dry-run)"

echo "Done. Check the alert email and run scripts/capture-evidence.sh next."
