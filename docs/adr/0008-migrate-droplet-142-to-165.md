# Migrated from droplet 142.93.166.76 to a new droplet, 165.22.16.160

The original droplet ran Ubuntu 20.04 (focal), which by 2026 had fallen out
of standard support and — critically — the `ondrej/php` PPA had stopped
publishing packages for it entirely (confirmed by checking its raw package
index: an empty `Packages` file for every PHP version on focal). Since
adding PHP site support was the actual goal, an in-place two-hop OS upgrade
(20.04→22.04→24.04) was attempted first but judged too risky for a live
production box with no snapshot taken (user's explicit call, accepting the
risk given low traffic) — a fresh droplet on Ubuntu 24.04 (noble) sidesteps
that entirely and let us redeploy everything through the very scripts this
repo exists to provide, rather than patching a decade of accumulated cruft
in place (90+ unpurged old kernels, a mixed apt/nvm Node setup that quietly
depended on an EOL package, dead PPAs, no firewall).

Both droplets were later resized from 1GB to 2GB RAM after real memory
pressure appeared once PHP-FPM and multiple sites were added — both
resizes were verified to survive a full reboot cleanly (all PM2 services,
0 restarts) before proceeding.

**Migration approach:** services were redeployed fresh (git clone + build)
on the new droplet rather than disk-imaged, with only secrets (`.env`
files, `CROSS_CHECK_PSK` values) and genuinely irreplaceable data (the
940MB Syzygy chess tablebase) copied directly droplet-to-droplet via
`scp -3` / a temporary SSH key — never passing through this repo's
operator's own visible context. `chess-analysis-gui` (the static site) is
a partial exception: its old webpack 4 toolchain doesn't build cleanly on
modern Node (OpenSSL 3 and strict ESM `exports` incompatibilities both hit
in the same session), so the already-built `build/` output was copied
directly from the old droplet as a working stopgap, with a proper rebuild
against modernized tooling deferred (see `inventory/services.yml`'s note
on `chess-analysis-gui`).

**Cutover is staged, not atomic:** each domain's DNS is moved independently
as it becomes ready (`inventory/domains.yml` tracks per-domain status), so
the old droplet keeps serving whatever hasn't cut over yet. The old droplet
is only safe to delete once every domain in `inventory/domains.yml` has
been confirmed serving correctly from the new droplet over HTTPS.
