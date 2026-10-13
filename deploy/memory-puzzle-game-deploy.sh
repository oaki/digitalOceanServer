#!/usr/bin/env bash
# Forced command for the dedicated GitHub Actions deployment key.
# Receives a 40-character commit SHA in SSH_ORIGINAL_COMMAND and a gzipped
# Next.js standalone release on stdin. Builds happen in CI, not on the droplet.
set -euo pipefail
umask 022

export PATH=/root/.nvm/versions/node/v24.18.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

APP=/opt/apps/memory-puzzle-game
RELEASES=/opt/apps/memory-puzzle-game-releases
CURRENT=/opt/apps/memory-puzzle-game-current
RUNTIME_CONFIG=/opt/apps/memory-puzzle-game-runtime.config.cjs
NODE=/root/.nvm/versions/node/v24.18.1/bin/node
MAX_ARCHIVE_BYTES=$((250 * 1024 * 1024))
MAX_UNPACKED_BYTES=$((750 * 1024 * 1024))

fail() { echo "deploy: $*" >&2; exit 1; }

exec 9>/run/lock/memory-puzzle-game-deploy.lock
flock -n 9 || fail "another deploy is running"

sha="${SSH_ORIGINAL_COMMAND:-}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "expected a 40 character commit id"
[[ -f "$APP/.env" ]] || fail "missing $APP/.env"

work=$(mktemp -d /opt/apps/.memory-puzzle-game-deploy.XXXXXX)
trap 'rm -rf "$work"' EXIT
chmod 711 "$work"

head -c $((MAX_ARCHIVE_BYTES + 1)) > "$work/release.tgz"
size=$(stat -c %s "$work/release.tgz")
(( size > 0 && size <= MAX_ARCHIVE_BYTES )) || fail "release archive is empty or too large"
gzip -t < "$work/release.tgz" 2>/dev/null || fail "release archive is not valid gzip"
{ gzip -dc < "$work/release.tgz" 2>/dev/null || true; } | head -c $((MAX_UNPACKED_BYTES + 1)) > "$work/release.tar"
(( $(stat -c %s "$work/release.tar") <= MAX_UNPACKED_BYTES )) || fail "release archive expands beyond the limit"

install -d -o nobody -g nogroup -m 700 "$work/release"
setpriv --reuid=nobody --regid=nogroup --clear-groups --no-new-privs \
  tar -xf "$work/release.tar" -C "$work/release" --no-same-owner --no-same-permissions || fail "release archive could not be unpacked"
[[ -z "$(find "$work/release" ! -type f ! -type d ! -type l -print -quit)" ]] || fail "release archive contains special files"
[[ -z "$(find "$work/release" -type f -links +1 -print -quit)" ]] || fail "release archive contains hard links"
while IFS= read -r -d '' link; do
  resolved=$(realpath -m "$link")
  [[ "$resolved" == "$work/release/"* && -e "$link" ]] || fail "release contains an unsafe or broken link"
done < <(find "$work/release" -type l -print0)
[[ -f "$work/release/server.js" ]] || fail "release has no standalone server"
[[ -f "$work/release/.next/BUILD_ID" ]] || fail "release has no Next.js build id"
[[ ! -e "$work/release/.env" ]] || fail "release must not contain an environment file"
chown -R root:root "$work/release"

cd "$APP"
git diff --quiet && git diff --cached --quiet || fail "the server clone has local changes"
git fetch --quiet origin main
git merge-base --is-ancestor "$sha" origin/main || fail "$sha is not on origin/main"
previous=$(git rev-parse HEAD)
git merge-base --is-ancestor "$previous" "$sha" || fail "$sha is older than deployed commit $previous"
git merge --ff-only --quiet "$sha"

install -d -m 755 "$RELEASES"
target="$RELEASES/$sha"
rm -rf "$target"
mv "$work/release" "$target"

previous_target=""
[[ -L "$CURRENT" ]] && previous_target=$(readlink -f "$CURRENT")
ln -s "$target" "$work/current"
mv -Tf "$work/current" "$CURRENT"

cat > "$RUNTIME_CONFIG" <<EOF
module.exports = {
  apps: [{
    name: "memory-puzzle-game",
    script: "$NODE",
    args: ["--env-file=$APP/.env", "$CURRENT/server.js"],
    cwd: "$CURRENT",
    env: { NODE_ENV: "production", PORT: "3008", HOSTNAME: "127.0.0.1" }
  }]
};
EOF

pm2 delete memory-puzzle-game >/dev/null 2>&1 || true
pm2 start "$RUNTIME_CONFIG" --update-env >/dev/null
ready=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null http://127.0.0.1:3008/; then ready=1; break; fi
  sleep 1
done

if (( ! ready )); then
  if [[ -n "$previous_target" && -d "$previous_target" ]]; then
    ln -s "$previous_target" "$work/previous"
    mv -Tf "$work/previous" "$CURRENT"
    pm2 delete memory-puzzle-game >/dev/null 2>&1 || true
    pm2 start "$RUNTIME_CONFIG" --update-env >/dev/null || true
  else
    rm -f "$CURRENT"
    pm2 delete memory-puzzle-game >/dev/null 2>&1 || true
    (cd "$APP" && pm2 start npm --name memory-puzzle-game -- start -- -p 3008 >/dev/null) || true
  fi
  fail "new release did not become ready; restored the previous process"
fi

pm2 save >/dev/null
ls -1dt "$RELEASES"/* 2>/dev/null | tail -n +4 | xargs -r rm -rf
echo "deployed $sha (previous $previous)"
