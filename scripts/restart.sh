#!/usr/bin/env bash
# Restart a PM2 service without redeploying it.
# Usage: scripts/restart.sh SERVICE_NAME
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SERVICE_NAME="${1:?usage: restart.sh SERVICE_NAME}"
ssh_run "pm2 restart $SERVICE_NAME"
