#!/usr/bin/env bash
# Call the Umami API on the droplet's loopback with the stored API key.
# Usage: scripts/umami-api.sh METHOD /path [JSON_FILE]
#   scripts/umami-api.sh GET /websites/WEBSITE_ID/goals
#   scripts/umami-api.sh POST /websites/WEBSITE_ID/goals goal.json
# The path is relative to /api. The body is read locally and sent over SSH
# stdin, so no credential or payload ends up in a process list. Prints the
# response body; exits non-zero on an HTTP error.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

METHOD="${1:?usage: umami-api.sh METHOD /path [JSON_FILE]}"
API_PATH="${2:?usage: umami-api.sh METHOD /path [JSON_FILE]}"
BODY_FILE="${3:-}"
[[ "$METHOD" =~ ^(GET|POST|PUT|DELETE)$ ]] || { echo "METHOD must be GET, POST, PUT or DELETE" >&2; exit 1; }
[[ "$API_PATH" =~ ^/[A-Za-z0-9/_?=\&.%:-]*$ ]] || { echo "unsafe characters in path" >&2; exit 1; }

body="{}"
[ -n "$BODY_FILE" ] && body="$(cat "$BODY_FILE")"

printf '%s' "$body" | ssh "${SSH_OPTS[@]}" "$DROPLET_HOST" \
  "METHOD='$METHOD' API_PATH='$API_PATH' HAS_BODY='${BODY_FILE:+1}' /root/.nvm/versions/node/v24.18.1/bin/node -e '
const fs = require(\"node:fs\");
const key = fs.readFileSync(\"/opt/apps/umami/.api-key\", \"utf8\").trim();
const { METHOD, API_PATH, HAS_BODY } = process.env;
const body = fs.readFileSync(0, \"utf8\");
fetch(\"http://127.0.0.1:3009/api\" + API_PATH, {
  method: METHOD,
  headers: { Authorization: \"Bearer \" + key, \"Content-Type\": \"application/json\", Accept: \"application/json\" },
  body: HAS_BODY ? body : undefined,
}).then(async r => {
  const text = await r.text();
  if (!r.ok) { console.error(\"HTTP \" + r.status + \" \" + text); process.exit(1); }
  console.log(text);
}).catch(e => { console.error(e.message); process.exit(1); });
'"
