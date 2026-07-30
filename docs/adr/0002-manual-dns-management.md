# DNS is managed manually by the owner, not automated

New domains are registered and have their DNS records (A, MX, SPF, DKIM, TXT)
added by hand by the repo owner, wherever each domain happens to be registered
— not through DigitalOcean DNS or the DO API. We chose this because domains in
practice come from different registrars, and building DNS automation around
one provider (requiring a DO API token, or per-registrar integrations) isn't
worth it for the low frequency of adding a new domain. This repo's job is to
tell the owner the exact record to add and then handle everything
server-side (nginx vhost + Certbot) once it resolves — see
`docs/adding-a-domain.md`.
