#!/usr/bin/env bash
# Create (or find) the Umami website for DOMAIN and print its tracking snippet.
# Idempotent: running it twice for the same domain returns the same website id.
# Usage: scripts/add-analytics-site.sh DOMAIN [DISPLAY_NAME]
#
# Talks to Umami on the droplet's loopback (127.0.0.1:3009) with the API key in
# /opt/apps/umami/.api-key, so no credentials ever leave the droplet.
# Inserting the snippet into the site's code is a separate step: see
# docs/analytics.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

DOMAIN="${1:?usage: add-analytics-site.sh DOMAIN [DISPLAY_NAME]}"
NAME="${2:-$DOMAIN}"
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
  || { echo "DOMAIN must be a bare hostname like chess-analysis.com (no scheme, no path)" >&2; exit 1; }
[[ "$NAME" =~ ^[[:alnum:][:space:]._-]{1,100}$ ]] \
  || { echo "DISPLAY_NAME may only contain letters, digits, spaces, dot, dash, underscore" >&2; exit 1; }

UMAMI_URL="https://analytics.saniolabs.com"
ANALYTICS_YML="$REPO_ROOT/inventory/analytics.yml"

website_id="$(ssh "${SSH_OPTS[@]}" "$DROPLET_HOST" \
  "DOMAIN='$DOMAIN' NAME='$NAME' /root/.nvm/versions/node/v24.18.1/bin/node -" <<'JS'
const fs = require('node:fs');
const key = fs.readFileSync('/opt/apps/umami/.api-key', 'utf8').trim();
const api = 'http://127.0.0.1:3009/api';
const headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Accept: 'application/json' };
const { DOMAIN: domain, NAME: name } = process.env;

(async () => {
  const res = await fetch(`${api}/websites?search=${encodeURIComponent(domain)}&pageSize=100`, { headers });
  if (!res.ok) throw new Error(`list websites: HTTP ${res.status} ${await res.text()}`);
  const body = await res.json();
  const existing = (Array.isArray(body) ? body : body.data).find(w => w.domain === domain);
  if (existing) {
    console.error(`exists: ${existing.name} (${domain})`);
    console.log(existing.id);
    return;
  }
  const created = await fetch(`${api}/websites`, { method: 'POST', headers, body: JSON.stringify({ name, domain }) });
  if (!created.ok) throw new Error(`create website: HTTP ${created.status} ${await created.text()}`);
  const website = await created.json();
  console.error(`created: ${website.name} (${domain})`);
  console.log(website.id);
})().catch(e => { console.error(e.message); process.exit(1); });
JS
)"
[[ "$website_id" =~ ^[0-9a-f-]{36}$ ]] || { echo "unexpected website id: $website_id" >&2; exit 1; }

if ! grep -q "^  - domain: $DOMAIN$" "$ANALYTICS_YML"; then
  cat >> "$ANALYTICS_YML" <<EOF
  - domain: $DOMAIN
    website_id: $website_id
    added: $(date +%F)
    snippet_in: TODO   # repo + file where the <script> tag lives
EOF
  echo "==> Recorded in inventory/analytics.yml (fill in snippet_in once the tag is in the site's code)" >&2
fi

# data-domains makes the tracker ignore localhost, preview and staging hosts,
# so the snippet can ship unconditionally. www and the bare name both count.
apex="${DOMAIN#www.}"
echo "website_id: $website_id"
echo "dashboard:  $UMAMI_URL/websites/$website_id"
echo "snippet:"
echo "<script defer src=\"$UMAMI_URL/script.js\" data-website-id=\"$website_id\" data-domains=\"$apex,www.$apex\"></script>"
