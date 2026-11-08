#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

POLICY_FILE="$ROOT/policies/least-privilege-policy.json"

BUCKET_ARN="arn:aws:s3:::article05-demo-bucket"
OBJECT_ARN="arn:aws:s3:::article05-demo-bucket/telemetry/sample.json"

command -v aws >/dev/null || {
    echo "ERROR: AWS CLI is required."
    exit 1
}

command -v python3 >/dev/null || {
    echo "ERROR: Python 3 is required."
    exit 1
}

# Convert the policy JSON object into a JSON array
# containing the policy document as a string.
POLICY_INPUT=$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    policy = json.load(f)

print(json.dumps([json.dumps(policy)]))
' "$POLICY_FILE")

run_case() {
    local label="$1"
    local action="$2"
    local resource="$3"

    echo
    echo "===== $label ====="
    echo "Action:   $action"
    echo "Resource: $resource"

    aws iam simulate-custom-policy \
        --policy-input-list "$POLICY_INPUT" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --query 'EvaluationResults[0].[EvalActionName,EvalResourceName,EvalDecision]' \
        --output table
}

run_case \
    "Expected allow" \
    "s3:PutObject" \
    "$OBJECT_ARN"

run_case \
    "Expected explicit deny" \
    "s3:DeleteBucket" \
    "$BUCKET_ARN"

run_case \
    "Expected implicit deny" \
    "s3:DeleteObject" \
    "$OBJECT_ARN"
