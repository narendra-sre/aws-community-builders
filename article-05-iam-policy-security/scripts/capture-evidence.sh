#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/evidence/results"

mkdir -p "$OUT"

command -v aws >/dev/null || {
  echo "ERROR: AWS CLI is required." >&2
  exit 1
}

# Store only command outputs. No caller identity, credentials, account ID,
# or ARN belonging to the user's account is collected by this script.

# 1. Run the local Python auditor
python3 "$ROOT/scripts/iam_policy_auditor.py" \
  "$ROOT/policies/overprivileged-policy.json" \
  "$ROOT/policies/least-privilege-policy.json" \
  > "$OUT/python-auditor-results.txt"

# 2. Validate both IAM policies using IAM Access Analyzer
for policy in overprivileged least-privilege; do
  aws accessanalyzer validate-policy \
    --policy-document "file://$ROOT/policies/${policy}-policy.json" \
    --policy-type IDENTITY_POLICY \
    --output json \
    > "$OUT/accessanalyzer-${policy}.json"
done

# 3. Convert the least-privilege policy into the format expected
#    by IAM SimulateCustomPolicy.
POLICY_INPUT="$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    policy = json.load(f)

print(json.dumps([json.dumps(policy)]))
' "$ROOT/policies/least-privilege-policy.json")"

# 4. Simulate selected IAM actions
BUCKET="arn:aws:s3:::article05-demo-bucket"
OBJECT="arn:aws:s3:::article05-demo-bucket/telemetry/sample.json"

: > "$OUT/simulator-results.txt"

for spec in \
  "s3:PutObject|$OBJECT" \
  "s3:DeleteBucket|$BUCKET" \
  "s3:DeleteObject|$OBJECT"
do
  action="${spec%%|*}"
  resource="${spec#*|}"

  printf '\n### %s on %s\n' "$action" "$resource" \
    >> "$OUT/simulator-results.txt"

  aws iam simulate-custom-policy \
    --policy-input-list "$POLICY_INPUT" \
    --action-names "$action" \
    --resource-arns "$resource" \
    --query 'EvaluationResults[0].[EvalActionName,EvalResourceName,EvalDecision]' \
    --output table \
    >> "$OUT/simulator-results.txt"
done

echo "Evidence saved to $OUT."
echo "Review it before committing; do not add credentials or unrelated account data."
