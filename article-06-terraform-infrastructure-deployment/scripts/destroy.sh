#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat <<'NOTICE'
This destroys Terraform-managed demonstration resources.
The S3 bucket has force_destroy=false. If it contains objects or versions,
Terraform may refuse deletion. Inspect it and remove only demo data you
intentionally created before retrying.
NOTICE
read -r -p "Type DESTROY to continue: " CONFIRM
if [[ "$CONFIRM" != "DESTROY" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi
terraform -chdir="$ROOT/terraform" destroy
