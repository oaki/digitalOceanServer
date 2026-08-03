#!/usr/bin/env bash
# Deploy a new PHP site on the shared PHP-FPM pool: clone, nginx vhost, Certbot.
# See docs/deploying-a-php-site.md. Assumes PHP-FPM is already installed
# (docs/adr/0007) — only works on Ubuntu 22.04/24.04 (jammy/noble).
# Usage: scripts/add-php-site.sh SITE_NAME REPO_URL DOMAIN
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SITE_NAME="${1:?usage: add-php-site.sh SITE_NAME REPO_URL DOMAIN}"
REPO_URL="${2:?usage: add-php-site.sh SITE_NAME REPO_URL DOMAIN}"
DOMAIN="${3:?usage: add-php-site.sh SITE_NAME REPO_URL DOMAIN}"

echo "==> Checking DNS for $DOMAIN"
resolved="$(dig +short "$DOMAIN" | tail -1)"
if [ -z "$resolved" ]; then
  echo "ERROR: $DOMAIN does not resolve yet. Add the A record first (see docs/adding-a-domain.md)." >&2
  exit 1
fi

echo "==> Cloning to /opt/apps/$SITE_NAME"
ssh_run "cd /opt/apps && git clone $REPO_URL $SITE_NAME"

echo "==> Writing nginx vhost for $DOMAIN"
ssh_run "cat > /etc/nginx/sites-enabled/$SITE_NAME << 'EOF'
server {
    server_name $DOMAIN;
    root /opt/apps/$SITE_NAME;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|svg|woff|woff2|ttf|eot|ico)\$ {
        expires 1y;
        add_header Cache-Control \"public, immutable\";
        try_files \$uri =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    listen 80;
}
EOF
nginx -t && systemctl reload nginx"

echo "==> Requesting SSL cert"
ssh_run "certbot --nginx -d $DOMAIN --non-interactive --agree-tos --redirect --email pavolbincik@gmail.com"

echo "==> Enabling HTTP/2 (certbot doesn't add this itself)"
ssh_run "sed -i -E 's/listen ([^;]*)443 ssl;/listen \1443 ssl http2;/' /etc/nginx/sites-enabled/$SITE_NAME && nginx -t && systemctl reload nginx"

echo "==> Verifying"
ssh_run "curl -s -o /dev/null -w 'HTTP %{http_code}\n' https://$DOMAIN/"

echo "==> Done: https://$DOMAIN"
echo "==> Now add this site's entry (name, dir, repo, domain, env_keys) to inventory/services.yml under php_sites"
