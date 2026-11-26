#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
  echo "Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars first."
  exit 1
fi
terraform -chdir="$TF_DIR" fmt -recursive
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" plan -out=article09.tfplan
read -r -p "Review the plan. Type APPLY to create billable resources: " CONFIRM
if [[ "$CONFIRM" != "APPLY" ]]; then echo "Cancelled."; exit 0; fi
terraform -chdir="$TF_DIR" apply article09.tfplan
rm -f "$TF_DIR/article09.tfplan"
