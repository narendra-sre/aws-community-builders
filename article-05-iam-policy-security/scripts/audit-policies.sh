#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/scripts/iam_policy_auditor.py" \
  "$ROOT/policies/overprivileged-policy.json" \
  "$ROOT/policies/least-privilege-policy.json"
