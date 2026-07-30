#!/usr/bin/env bash
# Show what's running on the droplet: PM2 processes, disk, memory.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

ssh_run "pm2 list && echo --- && df -h / && echo --- && free -h"
