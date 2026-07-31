# Deploying a new Static Site

A **Static Site** (see CONTEXT.md) is git-deployed but has no PM2 process and
no port — nginx serves its built files directly. Use
`scripts/add-static-site.sh`.

## Steps

1. **Clone + build** on the droplet:
   ```bash
   cd /opt/apps && git clone GIT_REPO_URL SITE_NAME && cd SITE_NAME && npm install && npm run build
   ```
   (skip `npm run build` for a plain HTML/CSS/JS site with no build step)
2. **nginx vhost** at `/etc/nginx/sites-enabled/SITE_NAME`, serving files
   directly — no `proxy_pass`, no port:
   ```nginx
   server {
       server_name DOMAIN;
       root /opt/apps/SITE_NAME/BUILD_OUTPUT_DIR;
       index index.html;
       try_files $uri $uri/ /index.html?$args;
       listen 443 ssl;
       ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
       include /etc/letsencrypt/options-ssl-nginx.conf;
       ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
   }
   ```
   then `nginx -t && systemctl reload nginx`.
3. **Certbot:**
   ```bash
   certbot --nginx -d DOMAIN --non-interactive --agree-tos --email pavolbincik@gmail.com
   ```
4. **Update inventory** — append to the `static_sites` list in
   `inventory/services.yml` (name, dir, repo, build_output, domain).

## Redeploying

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "cd /opt/apps/SITE_NAME && git pull && npm install && npm run build"
```
No PM2/nginx restart needed — nginx reads the rebuilt files from disk on the
next request.
