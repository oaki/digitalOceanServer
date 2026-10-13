#!/usr/bin/env bash
set -euo pipefail

exec 9>/run/lock/contexthub-deploy.lock
flock -n 9 || { echo "A ContextHub deployment is already running."; exit 1; }

if [ ! -d /opt/apps/contexthub/.git ]; then
  git clone https://github.com/oaki/contexthub.git /opt/apps/contexthub
fi

cd /opt/apps/contexthub
git fetch origin main
git checkout main
git merge --ff-only origin/main

test -s index.html
test -s styles.css
test -s script.js
