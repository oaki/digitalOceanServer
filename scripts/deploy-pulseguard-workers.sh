#!/usr/bin/env bash
# Redeploy both pulseGuard monorepo workers after upstream changes.
# See docs/adr/0006-shared-monorepo-clone-for-pulseguard-workers.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

ssh_run "cd /opt/pulseGuard-monorepo && git pull && pm2 restart pulseguard-ping-worker pulseguard-uptime-worker"
