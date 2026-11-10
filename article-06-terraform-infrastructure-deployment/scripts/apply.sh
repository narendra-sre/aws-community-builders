#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Review the Terraform plan carefully before approving."
terraform -chdir="$ROOT/terraform" apply
