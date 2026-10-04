# Deploying the private video-call system

The private video-call monorepo is deployed at `/opt/apps/videocall` from the
private `oaki/videocall` repository. One checkout produces two PM2 Services:

- `videocall-api` on loopback port 3005;
- `videocall-web` on loopback port 3006.

LiveKit is a separate `videocall-livekit.service` systemd unit. PostgreSQL and
all application process ports remain private. nginx exposes the single public
domain `call.contexthub.uk`, including LiveKit's `/rtc` WebSocket signaling.

## Network ports

- TCP 80/443: nginx and TLS;
- TCP 7881: LiveKit ICE fallback;
- UDP 7882: LiveKit ICE media mux;
- UDP 3478: TURN/UDP;
- TCP 5349: TURN/TLS.

The last four ports must be allowed by both UFW and any DigitalOcean Cloud
Firewall attached to the droplet.

## Secrets

`/opt/apps/videocall/.env` and `/etc/livekit/livekit.yaml` exist only on the
droplet. Their values are not copied into this repository. The API and LiveKit
must share the same generated key and secret. PostgreSQL uses a dedicated role
and database.

The repository deploy key uses the droplet SSH alias `github-videocall` and is
read-only for `oaki/videocall`.

## Regular deployment

After the application commit has passed CI:

```sh
scripts/deploy-videocall.sh
```

The script fast-forwards the checkout, installs the frozen pnpm lockfile,
builds both Node applications with the droplet-only environment, reloads PM2,
and verifies the API, PWA, and LiveKit unit.

## Verification

```sh
curl -fsS https://call.contexthub.uk/health
scripts/logs.sh videocall-api
scripts/logs.sh videocall-web
ssh -i ~/.ssh/id_ed25519 root@165.22.16.160 \
  "systemctl status videocall-livekit --no-pager"
```

The physical call and headset acceptance remains the checklist in the
application repository's `docs/milestone-17.md`.
