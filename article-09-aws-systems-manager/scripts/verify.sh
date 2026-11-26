#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
INSTANCE_ID="$(terraform -chdir="$TF_DIR" output -raw instance_id)"
REGION="$(terraform -chdir="$TF_DIR" output -raw aws_region)"
SG_ID="$(terraform -chdir="$TF_DIR" output -raw security_group_id)"
echo "== EC2 instance =="
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].{State:State.Name,InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}' --output table
echo "== Security group ingress (expected empty) =="
aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" --query 'SecurityGroups[0].IpPermissions' --output json
echo "== SSM managed-node status =="
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --region "$REGION" --output table
echo "If not listed yet, wait a few minutes and run this script again."
