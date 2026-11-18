#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
SG="$(terraform -chdir="$TF_DIR" output -raw test_security_group_id)"
REGION="$(terraform -chdir="$TF_DIR" output -raw aws_region)"
CIDR="203.0.113.0/24"
PORT=22
echo "This test adds TCP/$PORT from documentation-only CIDR $CIDR to the dedicated demo SG."
read -r -p "Type TEST to continue: " answer
[[ "$answer" == "TEST" ]] || { echo "Test cancelled."; exit 1; }
cleanup_rule() {
  aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port "$PORT" --cidr "$CIDR" --region "$REGION" >/dev/null 2>&1 || true
}
trap cleanup_rule EXIT
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port "$PORT" --cidr "$CIDR" --region "$REGION"
echo "Ingress API call submitted. Allow time for CloudTrail/EventBridge/SNS delivery."
echo "Check the confirmed SNS email subscription."
sleep 15
cleanup_rule
trap - EXIT
echo "Temporary ingress rule removal requested. Verify the rule is absent."
