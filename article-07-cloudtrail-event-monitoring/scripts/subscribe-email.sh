#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 YOUR_EMAIL_ADDRESS" >&2; exit 2; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOPIC_ARN="$(terraform -chdir="$ROOT_DIR/terraform" output -raw sns_topic_arn)"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$1"
echo "Check your inbox and confirm the SNS subscription before testing."
