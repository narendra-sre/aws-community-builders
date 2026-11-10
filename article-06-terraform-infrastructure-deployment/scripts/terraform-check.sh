#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform -chdir="$ROOT/terraform" fmt -check -recursive
terraform -chdir="$ROOT/terraform" init -backend=false -input=false
terraform -chdir="$ROOT/terraform" validate
echo "Terraform formatting and validation checks passed."
