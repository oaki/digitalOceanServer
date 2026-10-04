#!/usr/bin/env bash
# Pull, build, and restart the already-provisioned private video-call service.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

ssh_run "cd /opt/apps/videocall && git pull --ff-only origin main && ./infra/production/build-and-restart.sh"
ssh_run "curl -fsS http://127.0.0.1:3005/health && curl -fsSI http://127.0.0.1:3006/ >/dev/null && systemctl is-active videocall-livekit"

echo "==> Deployed and verified: https://call.contexthub.uk"
