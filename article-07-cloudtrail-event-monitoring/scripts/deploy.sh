#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
read -r -p "Review the plan. Type APPLY to continue: " answer
[[ "$answer" == "APPLY" ]] || { echo "Deployment cancelled."; exit 1; }
terraform -chdir=terraform apply
