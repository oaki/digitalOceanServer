#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.nvm/versions/node/v24.18.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec 9>/run/lock/abakus-deploy.lock
flock -n 9 || { echo "An Abakus deployment is already running."; exit 1; }

if [ ! -d /opt/apps/abakus/.git ]; then
  git clone https://github.com/oaki/abakus.git /opt/apps/abakus
fi

cd /opt/apps/abakus
git fetch origin main
git checkout main
git merge --ff-only origin/main
npm ci
npm run build
