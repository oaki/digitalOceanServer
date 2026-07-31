#!/usr/bin/env bash
# Deploy a new Static Site: clone, build, nginx vhost, Certbot.
# Usage: scripts/add-static-site.sh SITE_NAME REPO_URL DOMAIN [BUILD_OUTPUT_DIR]
#
# DNS for DOMAIN must already resolve to 165.22.16.160 before running this —
# see docs/adding-a-domain.md. BUILD_OUTPUT_DIR defaults to "build".
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SITE_NAME="${1:?usage: add-static-site.sh SITE_NAME REPO_URL DOMAIN [BUILD_OUTPUT_DIR]}"
REPO_URL="${2:?usage: add-static-site.sh SITE_NAME REPO_URL DOMAIN [BUILD_OUTPUT_DIR]}"
DOMAIN="${3:?usage: add-static-site.sh SITE_NAME REPO_URL DOMAIN [BUILD_OUTPUT_DIR]}"
BUILD_OUTPUT_DIR="${4:-build}"

echo "==> Checking DNS for $DOMAIN"
resolved="$(dig +short "$DOMAIN" | tail -1)"
if [ "$resolved" != "165.22.16.160" ]; then
  echo "ERROR: $DOMAIN resolves to '${resolved:-nothing}', not 165.22.16.160." >&2
  echo "Add the A record first (see docs/adding-a-domain.md) and wait for it to propagate." >&2
  exit 1
fi

echo "==> Cloning + building on the droplet"
ssh_run "cd /opt/apps && git clone $REPO_URL $SITE_NAME && cd $SITE_NAME && npm install && npm run build"

echo "==> Writing nginx vhost"
ssh_run "cat > /etc/nginx/sites-enabled/$SITE_NAME << 'EOF'
server {
    server_name $DOMAIN;
    root /opt/apps/$SITE_NAME/$BUILD_OUTPUT_DIR;
    index index.html;
    try_files \$uri \$uri/ /index.html?\$args;
    listen 80;
}
EOF
nginx -t && systemctl reload nginx"

echo "==> Requesting SSL cert"
ssh_run "certbot --nginx -d $DOMAIN --non-interactive --agree-tos --redirect --email pavolbincik@gmail.com"

echo "==> Done. Now add an entry to inventory/services.yml under static_sites:"
cat <<EOF

  - name: $SITE_NAME
    dir: $SITE_NAME
    repo: $REPO_URL
    build_output: $BUILD_OUTPUT_DIR
    domain: $DOMAIN
EOF
