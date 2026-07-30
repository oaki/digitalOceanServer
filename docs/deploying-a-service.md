# Deploying a new Service (Node.js + PM2)

A **Service** (see CONTEXT.md) is a git-deployed Node.js process managed by
PM2 and reverse-proxied by nginx. Use `scripts/add-service.sh` rather than
running these steps by hand — it does the same thing, reading/writing
`inventory/services.yml` for you.

## What the script does, in order

1. **Pick a port** — reads `next_free_port` from `inventory/services.yml`
   (see `docs/adr/0005-inventory-authoritative-for-ports.md`).
2. **Clone + build** on the droplet:
   ```bash
   cd /opt/apps && git clone GIT_REPO_URL SERVICE_NAME && cd SERVICE_NAME && npm install && npm run build
   ```
3. **Copy the `.env` file** via `scp` (not embedded in the SSH command —
   avoids leaking secret values into shell history or process listings on
   either end):
   ```bash
   scp -i ~/.ssh/id_ed25519 LOCAL_ENV_FILE root@142.93.166.76:/opt/apps/SERVICE_NAME/.env
   ```
4. **Start with PM2:**
   ```bash
   cd /opt/apps/SERVICE_NAME && pm2 start dist/index.js --name SERVICE_NAME && pm2 save
   ```
   If the entry point isn't `dist/index.js`, check `package.json`'s `main`
   field or the build output first.
5. **nginx vhost** at `/etc/nginx/sites-enabled/SERVICE_NAME`, proxying
   `SERVICE_NAME.chess-analysis.com` → `localhost:PORT`, then
   `nginx -t && systemctl reload nginx`.
6. **Certbot:**
   ```bash
   certbot --nginx -d SERVICE_NAME.chess-analysis.com --non-interactive --agree-tos --email pavolbincik@gmail.com
   ```
7. **Verify:** `pm2 list` shows it online, and
   `curl -s -o /dev/null -w '%{http_code}' http://localhost:PORT/` responds.
8. **Update inventory** — append the new entry to `inventory/services.yml`
   (name, dir, repo, port, domain, env_keys — key *names* only, never
   values) and bump `next_free_port`.

## Naming convention

For every **new** service: `name == directory == PM2 process name ==
subdomain prefix`. Two existing services (`pulseguard-worker`,
`pulseguard-uptime-worker`) don't follow this and aren't git repos either —
see the `drift` notes in `inventory/services.yml`. Don't propagate that
pattern to new services.

## Redeploying an existing service

```bash
scripts/deploy.sh SERVICE_NAME
```
Runs `git pull && npm install && npm run build && pm2 restart SERVICE_NAME`
on the droplet.
