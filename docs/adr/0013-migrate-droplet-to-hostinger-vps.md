# Migrate the Droplet (165.22.16.160) to a larger Hostinger VPS (187.7.19.10)

The Droplet has 1 vCPU and 2 GB RAM and is out of memory headroom (about 320 MB available, 800 MB of swap in use) with ten PM2 processes, PostgreSQL, Redis, LiveKit and PHP-FPM on it. The VPS has 4 vCPU, 15 GB RAM and 193 GB disk. Everything that still matters moves there; the step-by-step plan is `docs/migration-to-vps.md`. This ADR records the choices that are hard to reverse and would surprise a future reader. It follows ADR-0008, which moved from the first droplet using the same staged approach.

**OS stays Ubuntu 26.04 on the VPS**, even though every script and ADR-0007 were written for 24.04. The VPS shipped with 26.04 and the owner chose to keep it. Package availability was checked first, with one correction found during execution: PGDG publishes a populated `resolute` suite, but the ondrej PHP PPA's `resolute` index is empty (its `Release` file exists, so a Release check alone is misleading), so PHP 8.5 comes from the Ubuntu archive instead of 8.4 from the PPA; Laravel 13.23 and `siebi.sk` run on it. nginx, Redis, Postfix and certbot come from the archive, Node from nvm. Chrome dependencies for the Consent Runner and AppArmor user-namespace rules are untested on 26.04, which is why that service is an optional last step.

**PostgreSQL 16 from PGDG, not the archive's 18.** The OS already changes in this migration; the database major version should not change with it. The four databases use only `pgcrypto`, so moving to 18 later is a separate `pg_upgrade` or dump and restore.

**Cutover is staged per service, never all at once**, as in ADR-0008. A service takes its database with it at its own Cutover and the Droplet stays untouched, so rollback is a DNS change. The wildcard `*.chess-analysis.com` is DNS-managed at DigitalOcean, so subdomains get explicit A records to be switched individually; the wildcard moves last.

**TLS: `/etc/letsencrypt` is copied from the Droplet before Cutover.** certbot's HTTP-01 flow only issues once DNS already points at the VPS, which would leave a window without a valid certificate and break the standing HTTPS rule (docs/operations.md). Two servers briefly renewing the same certificates is tolerated by Let's Encrypt and ends when the Droplet is deleted.

**CI deploy target is the new IP written in each workflow**, not a stable hostname. The change is needed in seven repositories either way (hard-coded IP in four, and the `DEPLOY_KNOWN_HOSTS` secret holds the old host key in six); a hostname would only save work on a future migration at the cost of one more DNS record.

**Backups: nightly `pg_dump` plus configuration, encrypted with `age`, uploaded to Cloudflare R2.** The Droplet had no database backups. Only the `age` public key lives on the server, so a compromised VPS cannot read old backups.

**Not migrated:** the v2 chess-analysis stack (`server` blue/green, `worker1`, Node 14), already stopped since 2026-10-31, and `chess-analysis-gui`, replaced on 2026-10-05. Before the Droplet is deleted their directories are archived locally (encrypted), not on the VPS. The Droplet is kept for 7 days after the last Cutover as the rollback window, shorter than the 14 days first considered, accepted by the owner.
