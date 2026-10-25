# Self-hosted Umami, built locally and run under PM2 - no Docker on the droplet

Web analytics for every site on the droplet goes to one self-hosted Umami
instance at `analytics.saniolabs.com` (Service `umami`, port 3009, database
`umami` on the droplet's existing PostgreSQL 16). One instance, one website
profile per site, created through Umami's API by
`scripts/add-analytics-site.sh`.

## Why not Umami's Docker image

Docker is not installed on the droplet, and the droplet has 2 GB RAM with
roughly 300 MB available and swap already in use (measured 2026-10-25).
The Docker daemon plus containerd would cost memory for no benefit here:
everything Umami needs at runtime (Node 24, PostgreSQL 16, PM2, nginx,
Certbot) is already on the droplet and managed the same way as every other
Service.

## Why build locally instead of on the droplet

`next build` for Umami needs well over 1 GB RAM, the same problem that made
`chess-analysis-v3-web` a locally built static export. Building on the
droplet would push running Services into swap or the OOM killer.
`scripts/deploy-umami.sh` therefore clones a tagged release, builds it in a
`linux/amd64` Debian Node container on the control machine (mirroring the
builder and runner stages of Umami's own Dockerfile, but glibc instead of
Alpine musl, to match Ubuntu), uploads the result, runs migrations and
switches a `current` symlink. Prisma 7 runs with the JS query compiler
(`engineType = "client"`), so the only native binary in the release is the
migration engine, which the container installs for linux-x64.

## Consequences

- Upgrading Umami is `scripts/deploy-umami.sh vX.Y.Z` from the control
  machine; it needs a running local Docker daemon.
- The previous release stays on disk next to the active one, and the deploy
  rolls the symlink back if the health check fails.
- The Node heap is capped at 256 MB and PM2 restarts the process above
  400 MB RSS, so a leak in Umami cannot starve the other Services.
- Credentials (admin password, API key for the script) live only on the
  droplet in `/opt/apps/umami/`, mode 600.
