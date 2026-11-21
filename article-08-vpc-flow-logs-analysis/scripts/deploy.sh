#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
read -r -p "Review plan. Type APPLY to create resources: " answer
[[ "$answer" == "APPLY" ]] || { echo "Cancelled"; exit 1; }
terraform apply tfplan
rm -f tfplan
