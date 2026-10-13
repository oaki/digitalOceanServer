#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.nvm/versions/node/v24.18.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec 9>/run/lock/memory-puzzle-game-deploy.lock
flock -n 9 || { echo "A Memory Puzzle deployment is already running."; exit 1; }

if [ ! -d /opt/apps/memory-puzzle-game/.git ]; then
  git clone git@github-memory-puzzle-game:oaki/memory-puzzle-game.git /opt/apps/memory-puzzle-game
fi

cd /opt/apps/memory-puzzle-game
git fetch origin main
git checkout main
git merge --ff-only origin/main
npm ci
npm run build
if pm2 describe memory-puzzle-game >/dev/null 2>&1; then
  pm2 restart memory-puzzle-game --update-env
else
  pm2 start npm --name memory-puzzle-game -- start -- -p 3008
fi
pm2 save
