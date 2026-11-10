#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
command -v aws >/dev/null || { echo "ERROR: AWS CLI is required." >&2; exit 1; }

BUCKET="$(terraform -chdir="$TF_DIR" output -raw bucket_name)"
REGION="$(terraform -chdir="$TF_DIR" output -raw bucket_region)"

echo "Verifying bucket: $BUCKET"
echo "Region: $REGION"
aws s3api head-bucket --bucket "$BUCKET" --region "$REGION"

echo
echo "Public access block:"
aws s3api get-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --query 'PublicAccessBlockConfiguration' --output table

echo
echo "Versioning:"
aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" --output json

echo
echo "Default encryption:"
aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
  --query 'ServerSideEncryptionConfiguration.Rules[*].ApplyServerSideEncryptionByDefault' \
  --output table

echo
echo "Ownership controls:"
aws s3api get-bucket-ownership-controls --bucket "$BUCKET" --region "$REGION" --output json

echo
echo "Verification commands completed. Review each returned setting."
