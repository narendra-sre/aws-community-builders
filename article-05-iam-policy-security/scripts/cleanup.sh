#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "This project does not create AWS resources. No AWS teardown is required."
echo "To remove only local generated evidence, run: rm -rf '$ROOT/evidence/results'/*"
