# Baromio Consent Runner runs as a sandboxed systemd unit, not a PM2 process

Every other Service on this droplet is a PM2 process (see CONTEXT.md). The Consent Runner
breaks that pattern deliberately: it repeatedly opens **arbitrary URLs supplied by Baromio
customers** in a real headless Chrome, so it needs kernel-enforced sandboxing, not just
process supervision. PM2 restarts a crashed process; it does nothing to stop that process
from reading `/opt/apps/*/.env`, reaching `localhost:6379` (Redis), or hitting the DigitalOcean
metadata endpoint if the page it's scanning tries to pivot.

The unit runs under `DynamicUser=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp`,
`PrivateDevices`, `NoNewPrivileges`, an explicit `InaccessiblePaths` list covering
`/opt/apps /etc/letsencrypt /etc/postfix /var/www`, and an `IPAddressDeny` covering loopback,
link-local, all private/CGNAT ranges, multicast, and the droplet's own public IPv4/IPv6 — so a
scanned page cannot reach anything else running here even if the renderer itself is
compromised. This hardening is not new: it's copied verbatim from
`workers/consent-spike/droplet/run-unit.sh` in the `pulseGuard` repo (Phase 0 spike), which
scanned 34 real customer sites under it with no production impact and no OOM (peak 635 MB
against a 700 MB cap). See `pulseGuard`'s
[ADR-0047](https://github.com/oaki/pulseGuard/blob/main/docs/adr/0047-consent-scan-runners-droplet-primary-cloudflare-capped-fallback.md)
for the full reasoning behind putting this runner on the droplet at all.

Chrome's own sandbox is not yet active (Ubuntu 24.04 refuses unprivileged user namespaces
without an AppArmor profile, which doesn't exist yet — that's a later, separate step). Until
it does, `CONSENT_RUNNER_ALLOWLIST` in `/etc/consent-runner.env` is the only thing stopping the
runner from navigating to an untrusted URL, so it's scoped to internal test hosts only, never
a real customer monitor URL, until the AppArmor profile lands.

## Code layout: sparse checkout, not manual file copy

`pulseGuard/workers/consent/droplet/README.md` describes copying `runner.mjs`, `package.json`
and `resolv.conf` by hand into `/opt/consent-runner`. That predates this droplet's now-standard
convention for pulseGuard code (see
[ADR-0006](0006-shared-monorepo-clone-for-pulseguard-workers.md)): everything comes from the
shared sparse checkout at `/opt/pulseGuard-monorepo`, symlinked into place, so a `git pull`
there updates every pulseGuard-sourced thing on the droplet at once instead of drifting out of
sync file by file. The Consent Runner follows the same pattern:

```bash
cd /opt/pulseGuard-monorepo
git sparse-checkout add workers/consent/core workers/consent/droplet
git pull
mkdir -p /opt/consent-runner
ln -s /opt/pulseGuard-monorepo/workers/consent/droplet/runner.mjs /opt/consent-runner/runner.mjs
ln -s /opt/pulseGuard-monorepo/workers/consent/droplet/package.json /opt/consent-runner/package.json
ln -s /opt/pulseGuard-monorepo/workers/consent/droplet/resolv.conf /opt/consent-runner/resolv.conf
ln -s /opt/pulseGuard-monorepo/workers/consent/core /opt/core
```

`ProtectSystem=strict` only blocks *writes* outside the unit's own paths — reading through a
symlink that resolves outside `/opt/consent-runner` is fine, same as it already is for the two
existing pulseguard workers. The node binary and `.cache/` (Chrome's downloaded
`chrome-headless-shell`) are NOT part of this — they're unversioned build artifacts, installed
directly into `/opt/consent-runner/node` and `/opt/consent-runner/.cache/`, outside the
monorepo checkout.

## Not tracked in inventory/services.yml

`services.yml`'s schema (ADR-0005) is PM2-specific — `port`, `node_interpreter`, PM2 process
name are all meaningless for a systemd unit with no port and no PM2 entry. Rather than bend
that schema to fit one non-PM2 service, the Consent Runner is tracked only here and in this
repo's runbooks; `systemctl status consent-runner.service` is the source of truth for whether
it's running, the same way `pm2 list` is for everything else. If a second non-PM2 systemd
service ever gets added, that's the point to reconsider a shared schema — not before.

## Consequences

- Operationally this droplet now has two supervision mechanisms (PM2 and systemd) instead of
  one. Anyone debugging "what's running here" needs to check both `pm2 list` and
  `systemctl list-units --type=service` — worth calling out since every existing runbook only
  mentions PM2.
- The Chrome library dependency list Chrome needs to launch at all wasn't actually recorded
  anywhere retrievable (the design plan claims "40 packages, recorded by the spike" but no such
  list exists in the `pulseGuard` repo) — determined fresh via `ldd` against the installed
  `chrome-headless-shell` binary and recorded in `docs/consent-runner-chrome-deps.md` in this
  repo, so it isn't lost a second time.
- `CONSENT_RUNNER_ALLOWLIST` remaining in place (not yet the AppArmor profile) is a known,
  deliberate gap, not an oversight — do not remove it without the AppArmor profile from
  `pulseGuard/workers/consent/droplet/README.md` step 7 being in place first.
