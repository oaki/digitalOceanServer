# Droplet Infrastructure

Domain glossary for managing the single Ubuntu droplet (`165.22.16.160`) that hosts
chess-analysis.com and related projects. This repo is the source of truth for what
runs on the droplet and how to change it — see `docs/` for runbooks, `inventory/`
for current state, `scripts/` for automation. It replaces the old `droplet` Claude
skill, which duplicated this knowledge in prose with no structured state.

## Language

**Droplet**:
The single Ubuntu 24.04 server at `165.22.16.160` that hosts every Service, Static
Site, Domain, and Mail Alias tracked in this repo.
_Avoid_: server (collides with the PM2 process literally named `server`), host, box.

**Service**:
A long-running Node.js process managed by PM2 on the droplet, reverse-proxied by
nginx from a subdomain to `localhost:PORT`. Deployed via git.
_Avoid_: app, process (too generic — a Service is specifically PM2-managed and
network-reachable; a background worker with no port is still a Service, just one
with `port: null`).

**Static Site**:
A git-deployed set of built files served directly by nginx (e.g. a React
`build/` folder) — no PM2 process, no port, no reverse proxy. Rebuilt in place on
`git pull` and served by pointing nginx's `root` at the build output.
_Avoid_: app, service (a Static Site has no running process to restart).

**PHP Site**:
A git-deployed site like a Static Site, but `.php` requests are handed to a
shared PHP-FPM pool instead of being served as static files or proxied to a
Node process. Requires PHP-FPM installed (only supported on Ubuntu 22.04/24.04
— see `docs/adr/0007-php-via-ondrej-ppa-shared-fpm-pool.md`).
_Avoid_: app, service (see Service for the Node/PM2 equivalent).

**Domain**:
A DNS name pointed at the droplet's IP. Registration and DNS records are managed
by the owner outside this repo (see ADR-0002) — this repo only tracks which
domains exist and what they route to (`inventory/domains.yml`).
_Avoid_: site (see Static Site / Service for what a domain actually routes to).

**Mail Alias**:
An address at a Domain (e.g. `info@siebi.sk`) that Postfix forwards to an
external mailbox the moment mail arrives. The droplet never stores the mail —
it is a relay, not a mail host (see ADR-0003).
_Avoid_: mailbox, email account — those imply local storage and IMAP access,
which this droplet deliberately does not provide.

**Deployment**:
Getting a project's code onto the droplet and (re)starting it: `git clone`/`git
pull` + build + `pm2 restart` for a Service, or `git pull` + build + nginx
reload for a Static Site. Always pull-based, always triggered by running a
script from the control machine (see ADR-0004) — never a push/CI pipeline.
_Avoid_: release, push, ship.

**Inventory**:
The YAML files under `inventory/` — the authoritative record of which Services,
Static Sites, Domains, and Mail Aliases exist, and which ports are taken (see
ADR-0005). Scripts read and write it directly; it is trusted over re-discovering
state live from the droplet (`pm2 list`, `ss -tlnp`), except when explicitly
reconciling drift.

**Drift**:
A mismatch between what `inventory/` says and what's actually running on the
droplet. Two Services (`pulseguard-worker`, `pulseguard-uptime-worker`) were
found in this state on 2026-07-30 — deployed by hand rather than via git, one
with a PM2 name that didn't match its subdomain — and were migrated the same
day onto a proper git-backed sparse checkout of their upstream monorepo (see
`docs/adr/0006-shared-monorepo-clone-for-pulseguard-workers.md`); the
port-3000 one was renamed `pulseguard-ping-worker` in the process. Recorded
here as the reference example of what "drift" means and how it gets resolved
— found, recorded in `inventory/`, then fixed deliberately rather than
silently.
