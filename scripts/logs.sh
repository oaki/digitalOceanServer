#!/usr/bin/env bash
# Tail the last 50 log lines for a PM2 service.
# Usage: scripts/logs.sh SERVICE_NAME
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SERVICE_NAME="${1:?usage: logs.sh SERVICE_NAME}"
ssh_run "pm2 logs $SERVICE_NAME --lines 50 --nostream"
