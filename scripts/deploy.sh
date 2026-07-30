#!/usr/bin/env bash
# Redeploy an existing git-based Service: pull, reinstall, rebuild, restart.
# Usage: scripts/deploy.sh SERVICE_NAME
#
# SERVICE_NAME must match a directory under /opt/apps/ and a PM2 process name.
# For the two Services in inventory/services.yml marked with a `drift` note
# (not actually git repos), this will fail at `git pull` — re-deploy those
# through scripts/add-service.sh instead to give them a proper git repo first.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SERVICE_NAME="${1:?usage: deploy.sh SERVICE_NAME}"
ssh_run "cd /opt/apps/$SERVICE_NAME && git pull && npm install && npm run build && pm2 restart $SERVICE_NAME"
