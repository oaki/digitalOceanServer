# inventory/services.yml is authoritative for port allocation

Adding a new Service picks its port from `inventory/services.yml`'s
`next_free_port`, rather than SSHing in and scanning `ss -tlnp` live each time.
This is faster and gives a readable single-glance list of what's running
without touching the droplet. The tradeoff is possible drift if something is
ever started on the droplet outside this repo's scripts (as already happened
once — see the `drift` notes in `services.yml`, dated 2026-07-30) — the
runbooks call out re-running `pm2 list` to cross-check whenever a port
conflict is suspected, rather than trusting the inventory blindly.
