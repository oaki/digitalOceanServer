# pulseguard-ping-worker and pulseguard-uptime-worker share one sparse monorepo checkout

Both workers' code actually lives inside `oaki/pulseGuard`, a private ~100MB
Laravel monorepo, as subdirectories (`workers/system`,
`workers/uptime/vps`) — not their own repos. Rather than cloning the whole
monorepo once per worker (200MB+ for code neither of them uses, on a droplet
already at 74% disk / ~235Mi free RAM), we clone it **once** at
`/opt/pulseGuard-monorepo` using `git sparse-checkout --cone` restricted to
just those two subdirectories (2MB on disk total), and symlink
`/opt/apps/pulseguard-ping-worker` / `/opt/apps/pulseguard-uptime-worker` to
the checked-out subdirectories. PM2's script paths (`/opt/apps/.../index.js`)
are unchanged by this — they just now resolve through a symlink — so no PM2
config had to move for the uptime worker; the ping worker was also renamed
(from `pulseguard-worker`) to match its long-standing domain
(`pulseguard-ping-worker.chess-analysis.com`), resolving a 3-way name
mismatch between PM2 process name, package.json name, and domain.

Since the monorepo is private, the droplet needed its own GitHub credential:
a dedicated **read-only SSH deploy key** was generated on the droplet and
added to `oaki/pulseGuard` (scoped to this one repo, can't push, revocable
any time from the repo's Deploy Keys settings) — see `~/.ssh/config`'s
`github-pulseguard` host alias on the droplet.

Redeploying either worker after a monorepo change:
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "cd /opt/pulseGuard-monorepo && git pull && pm2 restart pulseguard-ping-worker pulseguard-uptime-worker"
```

The old plain directories were kept as `*.pre-migration-backup` rather than
deleted immediately — safe to remove once both workers have run stably for a
while post-migration.
