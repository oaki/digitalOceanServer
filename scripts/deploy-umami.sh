#!/usr/bin/env bash
# Build an Umami release locally (linux/amd64 container) and activate it on
# the droplet. The droplet never builds: `next build` needs more RAM than the
# 2 GB droplet has free (see docs/adr/0012-self-hosted-umami-built-locally.md).
# Usage: scripts/deploy-umami.sh TAG        e.g. scripts/deploy-umami.sh v3.4.1
#
# Built releases are cached in ~/.cache/umami-releases/; a rerun with the same
# TAG skips the build and only uploads and activates (delete the file to force
# a rebuild).
#
# Runbook: docs/analytics.md. One-time setup (database, .env, nginx, TLS,
# admin password, API key) is documented there, not repeated here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

TAG="${1:?usage: deploy-umami.sh TAG (e.g. v3.4.1)}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "TAG must look like v3.4.1" >&2; exit 1; }

NODE_IMAGE="node:24.18.1-bookworm-slim"   # same major/minor as the droplet's nvm node
PNPM_VERSION="12.3.4"                     # Umami's package.json engines.pnpm
APP_DIR=/opt/apps/umami
NODE_BIN=/root/.nvm/versions/node/v24.18.1/bin
PORT=3009

CACHE_DIR="$HOME/.cache/umami-releases"
RELEASE="$CACHE_DIR/umami-$TAG.tgz"
mkdir -p "$CACHE_DIR"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ -f "$RELEASE" ] && gzip -t "$RELEASE" 2>/dev/null; then
  echo "==> Using cached build $RELEASE"
else
echo "==> Cloning umami $TAG"
git clone --quiet --depth 1 --branch "$TAG" https://github.com/umami-software/umami.git "$work/src"
# Keep in sync with the Dockerfile's PRISMA_VERSION for this tag.
PRISMA_VERSION="$(sed -nE 's/^ARG PRISMA_VERSION="([^"]+)"/\1/p' "$work/src/Dockerfile")"
[ -n "$PRISMA_VERSION" ] || { echo "could not read PRISMA_VERSION from Dockerfile" >&2; exit 1; }

echo "==> Building in $NODE_IMAGE (linux/amd64, prisma $PRISMA_VERSION) - takes several minutes"
mkdir -p "$work/out"
# Mirrors the builder + runner stages of Umami's own Dockerfile, but on Debian
# (glibc, like the droplet) instead of Alpine.
# openssl: without it Prisma assumes OpenSSL 1.1 and fetches a migration engine
# that cannot load on Ubuntu 24.04. The named volume caches the pnpm store
# between upgrades.
docker run --rm --platform linux/amd64 \
  -v "$work/src:/src:ro" -v "$work/out:/out" -v umami-pnpm-store:/pnpm-store \
  -e PNPM_VERSION="$PNPM_VERSION" -e PRISMA_VERSION="$PRISMA_VERSION" -e TAG="$TAG" \
  -e npm_config_store_dir=/pnpm-store \
  "$NODE_IMAGE" bash -euo pipefail -c '
    apt-get update -qq && apt-get install -y -qq --no-install-recommends openssl >/dev/null
    npm install -g --silent pnpm@$PNPM_VERSION
    cp -a /src/. /app && cd /app
    printf "strictDepBuilds: false\n" >> pnpm-workspace.yaml
    pnpm install --frozen-lockfile
    cp docker/proxy.ts src/   # runtime handling of TRACKER_SCRIPT_NAME etc., as in the Docker image
    DATABASE_URL=postgresql://user:pass@localhost:5432/dummy NEXT_TELEMETRY_DISABLED=1 DISABLE_TELEMETRY=1 \
      pnpm build:docker

    mkdir /rel && cd /rel
    echo {} > package.json
    printf "allowBuilds:\n  \"@prisma/engines\": true\n  prisma: false\nverifyDepsBeforeRun: false\n" > pnpm-workspace.yaml
    pnpm add dotenv chalk semver prisma@$PRISMA_VERSION @prisma/client@$PRISMA_VERSION @prisma/adapter-pg@$PRISMA_VERSION
    cp -a /app/public /app/prisma /app/prisma.config.ts /app/scripts /app/generated /app/geo .
    cp -a /app/.next/standalone/. .
    cp -a /app/.next/static .next/static
    rm -f .env
    tar -czf /out/umami-$TAG.tgz .
  '
mv "$work/out/umami-$TAG.tgz" "$RELEASE"
fi
ls -lh "$RELEASE"

echo "==> Uploading release"
ssh_run "install -d -m 700 $APP_DIR/releases"
# rsync --partial resumes a stalled transfer instead of starting over; a plain
# scp of this ~140 MB file once hung for over an hour without failing.
for attempt in 1 2 3; do
  rsync --partial --timeout=60 --stats \
    -e "ssh ${SSH_OPTS[*]} -o ServerAliveInterval=15 -o ServerAliveCountMax=4" \
    "$RELEASE" "$DROPLET_HOST:$APP_DIR/releases/umami-$TAG.tgz" && break
  [ "$attempt" = 3 ] && { echo "upload failed 3 times" >&2; exit 1; }
  echo "upload attempt $attempt failed, retrying" >&2
done

echo "==> Unpacking, migrating, switching, health-checking"
ssh_run "set -euo pipefail
export PATH=$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd $APP_DIR
[ -f .env ] || { echo 'missing $APP_DIR/.env - do the one-time setup in docs/analytics.md first' >&2; exit 1; }
rm -rf releases/$TAG && mkdir releases/$TAG
tar -xzf releases/umami-$TAG.tgz -C releases/$TAG && rm releases/umami-$TAG.tgz

# check-db.js runs 'prisma migrate deploy'; the release's own prisma CLI must win over anything on PATH.
(cd releases/$TAG && PATH=\$PWD/node_modules/.bin:\$PATH node --env-file=$APP_DIR/.env scripts/check-db.js)

previous=\$(readlink current 2>/dev/null || true)
ln -sfn releases/$TAG current.new && mv -Tf current.new current

cat > ecosystem.config.cjs <<EOF
module.exports = {
  apps: [{
    name: 'umami',
    script: '$APP_DIR/current/server.js',
    interpreter: '$NODE_BIN/node',
    node_args: ['--env-file=$APP_DIR/.env', '--max-old-space-size=256'],
    cwd: '$APP_DIR/current',
    max_memory_restart: '400M',
    env: { NODE_ENV: 'production', PORT: '$PORT', HOSTNAME: '127.0.0.1' }
  }]
};
EOF
pm2 startOrRestart ecosystem.config.cjs --update-env >/dev/null

for i in \$(seq 1 30); do
  curl -fs -o /dev/null http://127.0.0.1:$PORT/api/heartbeat && break
  sleep 2
done
if ! curl -fsS -o /dev/null http://127.0.0.1:$PORT/api/heartbeat; then
  echo 'health check failed' >&2
  if [ -n \"\$previous\" ]; then
    echo \"rolling back to \$previous\" >&2
    ln -sfn \"\$previous\" current.new && mv -Tf current.new current
    pm2 restart umami --update-env >/dev/null
  fi
  exit 1
fi
pm2 save >/dev/null

# Keep the active and the previous release only.
for dir in releases/*/; do
  dir=\${dir%/}
  [ \"\$dir\" = releases/$TAG ] || [ \"\$dir\" = \"\$previous\" ] || rm -rf \"\$dir\"
done
echo \"active: \$(readlink current)\""

echo "==> Done: umami $TAG on 127.0.0.1:$PORT (public: https://analytics.saniolabs.com)"
