# Adding a new domain

DNS is managed manually by the owner (see
`docs/adr/0002-manual-dns-management.md`) — this repo never touches DNS
records directly.

## Steps

1. **Tell the owner the exact record to add**, at whichever registrar/DNS
   provider the domain uses:
   ```
   Type: A
   Name: @ (or the subdomain, e.g. "app")
   Value: 142.93.166.76
   ```
   For a bare apex domain that needs `www` too, a second A (or CNAME, per the
   registrar's support for apex aliasing) record pointing `www` at the same IP.
2. **Wait for the owner to confirm DNS is live** — check with:
   ```bash
   dig +short DOMAIN
   ```
   It should return `142.93.166.76` before continuing.
3. **Deploy the Service or Static Site** that will live at this domain — see
   `docs/deploying-a-service.md` or `docs/deploying-a-static-site.md`, which
   both include their own nginx vhost + Certbot steps.
4. **Update `inventory/domains.yml`** with the new domain and what it routes to.

## Mail on a new domain

If the domain also needs an address like `info@DOMAIN`, that's a separate
step — see `docs/mail-alias.md`. It requires its own DNS records (MX, SPF)
which the owner also adds manually.
