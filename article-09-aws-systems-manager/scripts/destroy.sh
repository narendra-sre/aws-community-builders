#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
terraform -chdir="$TF_DIR" plan -destroy -out=article09-destroy.tfplan
read -r -p "Review the plan. Type DESTROY to remove the lab: " CONFIRM
if [[ "$CONFIRM" != "DESTROY" ]]; then echo "Cancelled."; exit 0; fi
terraform -chdir="$TF_DIR" apply article09-destroy.tfplan
rm -f "$TF_DIR/article09-destroy.tfplan"
