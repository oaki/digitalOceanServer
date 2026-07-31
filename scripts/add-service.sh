#!/usr/bin/env bash
# Deploy a new Node.js Service: pick a port, clone+build, copy .env, start
# with PM2, nginx vhost, Certbot. See docs/deploying-a-service.md.
# Usage: scripts/add-service.sh SERVICE_NAME REPO_URL [LOCAL_ENV_FILE]
#
# SERVICE_NAME is used as directory name, PM2 process name, and subdomain
# prefix (SERVICE_NAME.chess-analysis.com) — keep them identical for new
# services (see the naming convention note in docs/deploying-a-service.md).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

SERVICE_NAME="${1:?usage: add-service.sh SERVICE_NAME REPO_URL [LOCAL_ENV_FILE]}"
REPO_URL="${2:?usage: add-service.sh SERVICE_NAME REPO_URL [LOCAL_ENV_FILE]}"
LOCAL_ENV_FILE="${3:-}"
DOMAIN="$SERVICE_NAME.chess-analysis.com"
PORT="$(next_free_port)"

echo "==> Allocated port $PORT for $SERVICE_NAME"

echo "==> Cloning + building on the droplet"
ssh_run "cd /opt/apps && git clone $REPO_URL $SERVICE_NAME && cd $SERVICE_NAME && npm install && npm run build"

if [ -n "$LOCAL_ENV_FILE" ]; then
  echo "==> Copying .env via scp (not embedded in the ssh command)"
  scp_to_droplet "$LOCAL_ENV_FILE" "/opt/apps/$SERVICE_NAME/.env"
else
  echo "==> No env file given — skipping. Create /opt/apps/$SERVICE_NAME/.env on the droplet manually if needed."
fi

echo "==> Starting with PM2"
echo "    (check package.json's main/build output first if dist/index.js isn't the entry point)"
ssh_run "cd /opt/apps/$SERVICE_NAME && pm2 start dist/index.js --name $SERVICE_NAME && pm2 save"

echo "==> Writing nginx vhost for $DOMAIN -> localhost:$PORT"
ssh_run "cat > /etc/nginx/sites-enabled/$SERVICE_NAME << 'EOF'
server {
    server_name $DOMAIN;
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-NginX-Proxy true;
        proxy_pass http://localhost:$PORT/;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_session_reuse off;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
    }
    listen 80;
}
EOF
nginx -t && systemctl reload nginx"

echo "==> Requesting SSL cert"
ssh_run "certbot --nginx -d $DOMAIN --non-interactive --agree-tos --redirect --email pavolbincik@gmail.com"

echo "==> Verifying"
ssh_run "pm2 list | grep $SERVICE_NAME && curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:$PORT/"

echo "==> Bumping next_free_port to $((PORT + 1))"
set_next_free_port "$((PORT + 1))"

echo "==> Done: https://$DOMAIN"
echo "==> Now add this service's entry (name, dir, repo, port, domain, env_keys) to inventory/services.yml"
