# Common operations

All of these are also available as `scripts/*.sh` — see that directory.

## Default parking page for unconfigured domains

Both droplets have an nginx `default_server` catch-all
(`/etc/nginx/sites-available/000-default-catchall`, serving
`/opt/nginx-default/index.html`) for any domain that resolves here but has
no vhost yet — a wildcard DNS record added ahead of the actual site, or a
domain pointed here before deployment. Without this, an unmatched request
falls through unpredictably to whichever vhost nginx picks first (this
actually happened — random bot traffic with fake Host headers was landing on
`api.chess-analysis.com`'s vhost before this existed). The HTTPS side of the
catch-all uses the self-signed `ssl-cert` package cert (`snakeoil`) since
there's no way to get a publicly-trusted cert for a domain name we don't
know ahead of time — a browser warning here is expected, same as any
registrar's own default parking page.

**When adding a new droplet or vhost file:** never name a real, in-use vhost
file something implying it's disposable (`default`, `newDefault`, etc.) —
that ambiguity caused an actual near-incident here: `newDefault` on the old
droplet holds the real `chess-analysis.com`/`www`/`api` vhosts, and looked
enough like the standard placeholder to almost get deleted while setting up
this exact catch-all. Check a vhost file's actual `server_name` contents
before removing it, not just its filename.

## Standing rule: every domain redirects HTTP → HTTPS with a valid cert

Non-negotiable for every Domain in `inventory/domains.yml`, no exceptions.
Every `certbot --nginx` call in `scripts/*.sh` includes `--redirect` for this
reason — never issue a cert without it. If a domain is ever found serving
plain HTTP or with an expired/missing cert, that's a bug to fix immediately,
not a style choice.

**Check status** (`scripts/status.sh`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "pm2 list && df -h / && free -h"
```

**View logs** (`scripts/logs.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "pm2 logs SERVICE_NAME --lines 50 --nostream"
```

**Restart a service** (`scripts/restart.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "pm2 restart SERVICE_NAME"
```

**Redeploy** (`scripts/deploy.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "cd /opt/apps/SERVICE_NAME && git pull && npm install && npm run build && pm2 restart SERVICE_NAME"
```

**Disk usage:**
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "du -sh /opt/apps/* | sort -h"
```

## Performance

Baseline tuning applied to the new droplet (165.22.16.160) as of 2026-08-01:

- **gzip properly configured** in `/etc/nginx/nginx.conf` — it was already
  `on` but `gzip_types` was commented out, meaning only `text/html` (nginx's
  built-in default) was ever actually compressed; JS/CSS/JSON/SVG (including
  API responses) went out uncompressed until this was fixed.
- **HTTP/2 enabled** on every HTTPS vhost. Certbot's `--nginx` plugin does
  **not** add `http2` to the `listen 443 ssl;` line itself — `scripts/add-service.sh`,
  `add-static-site.sh`, and `add-php-site.sh` now do this as an explicit
  post-certbot step (`sed` on the vhost file), so it's automatic for every
  new site from here on. Check any hand-issued cert for this too.
- **Long-lived immutable caching for content-hashed static assets** (`Cache-Control:
  public, immutable`, 1 year) — added for `chess-analysis-gui`'s webpack
  output and `siebi.sk`'s Vite `/build/` output, both of which already use
  hashed filenames (safe to cache forever; a new deploy gets new filenames).
  `add-static-site.sh` and `add-php-site.sh` now include this by default.

**The droplet has only 1 vCPU** (the 1GB→2GB resize only added RAM, not
cores) — this is the real ceiling, not fixable by any nginx/PHP/Node config.
Every process (all Services, both PHP-FPM pools, nginx, Postfix) shares that
one core. This matters most for `worker1`'s Stockfish analysis, which is
CPU-bound and will contend with everything else on the box while running —
there's no second core to isolate it on. PM2 fork mode (not cluster) is
correct given this — cluster mode only helps with multiple cores. If real
concurrent load becomes a problem, a vCPU upgrade is the actual fix, not
further software tuning.

## Known operational risks (as of 2026-08-01)

These were found while setting up this repo and are worth acting on, but
weren't changed automatically since they touch system/security posture on a
live production box — confirm with the owner before applying:

- **`worker.chess-analysis.com`** has a valid Let's Encrypt cert but no
  matching nginx vhost or PM2 process — see the `drift` note in
  `inventory/domains.yml`. Not carried over to the new droplet.
- **Old droplet's large data files** (`export_strong_megabase2021.pgn.zip`
  ~400MB, `gm2700.pgn.zip` ~10MB) were never migrated to the new droplet —
  confirm whether anything still needs them before the old droplet is
  deleted (task: decommission old droplet).
