# Connecting to the droplet

- **Host:** `root@142.93.166.76`
- **SSH key:** `~/.ssh/id_ed25519`
- **OS:** Ubuntu 20.04, DigitalOcean Frankfurt (fra1)

Every command runs non-interactively — never open an interactive SSH session:

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@142.93.166.76 "COMMAND"
```

In practice, use `scripts/lib.sh`'s `ssh_run` function (see `docs/operations.md`
and any `scripts/*.sh`) instead of typing this out — it's the same pattern,
just not repeated everywhere.

## Directory layout on the droplet

- `/opt/apps/` — one directory per Service or Static Site, named to match
  `inventory/services.yml`
- `/etc/nginx/sites-available/` + `sites-enabled/` — one vhost per domain (or
  grouped into one file, as `newDefault` does for the four original
  chess-analysis.com subdomains)
- `/etc/letsencrypt/live/` — Certbot-managed certs; `certbot.timer` handles
  renewal automatically, no manual action needed
