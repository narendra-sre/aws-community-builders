#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v aws >/dev/null || { echo "ERROR: AWS CLI is required." >&2; exit 1; }
for policy in overprivileged least-privilege; do
  echo "===== Access Analyzer ValidatePolicy: ${policy} ====="
  aws accessanalyzer validate-policy \
    --policy-document "file://$ROOT/policies/${policy}-policy.json" \
    --policy-type IDENTITY_POLICY \
    --output json
 done
