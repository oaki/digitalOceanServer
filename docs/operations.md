# Common operations

All of these are also available as `scripts/*.sh` — see that directory.

**Check status** (`scripts/status.sh`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "pm2 list && df -h / && free -h"
```

**View logs** (`scripts/logs.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "pm2 logs SERVICE_NAME --lines 50 --nostream"
```

**Restart a service** (`scripts/restart.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "pm2 restart SERVICE_NAME"
```

**Redeploy** (`scripts/deploy.sh SERVICE_NAME`):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "cd /opt/apps/SERVICE_NAME && git pull && npm install && npm run build && pm2 restart SERVICE_NAME"
```

**Disk usage:**
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "du -sh /opt/apps/* | sort -h"
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
