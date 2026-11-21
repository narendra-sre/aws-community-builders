#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform plan -destroy -out=destroy.tfplan
read -r -p "This deletes the S3 bucket and its contents. Type DESTROY to continue: " answer
[[ "$answer" == "DESTROY" ]] || { echo "Cancelled"; exit 1; }
terraform apply destroy.tfplan
rm -f destroy.tfplan
