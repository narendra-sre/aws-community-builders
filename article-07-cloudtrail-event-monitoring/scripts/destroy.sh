#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform -chdir="$ROOT_DIR/terraform" plan -destroy
read -r -p "Type DESTROY to continue: " answer
[[ "$answer" == "DESTROY" ]] || { echo "Cleanup cancelled."; exit 1; }
terraform -chdir="$ROOT_DIR/terraform" destroy
