#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/evidence/results"
mkdir -p "$OUT"

{
  echo "=== Terraform version ==="
  terraform version
  echo
  echo "=== Terraform formatting check ==="
  terraform -chdir="$ROOT/terraform" fmt -check -recursive
  echo
  echo "=== Terraform validation ==="
  terraform -chdir="$ROOT/terraform" validate
  echo
  echo "=== Terraform outputs ==="
  terraform -chdir="$ROOT/terraform" output -no-color
} > "$OUT/terraform-summary.txt" 2>&1

"$ROOT/scripts/verify.sh" > "$OUT/aws-verification.txt" 2>&1
echo "Evidence saved under $OUT. Review and redact account-specific details before committing."
