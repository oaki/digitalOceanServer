#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.nvm/versions/node/v24.18.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec 9>/run/lock/saskamath-deploy.lock
flock -n 9 || { echo "A SaskaMath deployment is already running."; exit 1; }

if [ ! -d /opt/apps/saskamath/.git ]; then
  git clone git@github-saskamath:oaki/saskaMath.git /opt/apps/saskamath
fi

cd /opt/apps/saskamath
git fetch origin main
git checkout main
git merge --ff-only origin/main
npm ci
npm run build
