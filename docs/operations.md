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

## Known operational risks (as of 2026-07-30)

These were found while setting up this repo and are worth acting on, but
weren't changed automatically since they touch system/security posture on a
live production box — confirm with the owner before applying:

- **`ufw` is inactive** — no firewall in front of `sshd`/nginx. Recommended:
  enable `ufw` allowing only 22, 80, 443 (and 25/587 once mail is set up),
  after confirming SSH access still works.
- **Free memory is low** — ~235Mi available out of 964Mi total at last
  check. Adding another Node service risks OOM; consider a swapfile or
  upsizing the droplet before deploying much more.
- **Disk is 74% full** (6.4G free of 25G) — `/opt/apps/` has large data
  files sitting directly in it (`export_strong_megabase2021.pgn.zip` ~400MB,
  `gm2700.pgn.zip` ~10MB, a `syzygy/` tablebase dir) that aren't part of any
  tracked Service or Static Site — worth confirming these are still needed.
- **`worker.chess-analysis.com`** has a valid Let's Encrypt cert but no
  matching nginx vhost or PM2 process — see the `drift` note in
  `inventory/domains.yml`.
