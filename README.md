# digitalOceanServer

Infrastructure documentation & scripts for the DigitalOcean droplet at
`165.22.16.160` (Ubuntu 24.04, hosts chess-analysis.com and related
projects). This repo is the source of truth for what runs there and how to
change it — it replaced the old `droplet` Claude skill, which held the same
knowledge as unstructured prose with no tracked state.

- **[CONTEXT.md](./CONTEXT.md)** — domain glossary (Service, Static Site,
  Domain, Mail Alias, Deployment, Inventory)
- **[docs/](./docs/)** — runbooks: connecting, deploying a service, deploying
  a static site, adding a domain, adding a mail alias, common operations
- **[docs/adr/](./docs/adr/)** — why things are set up this way
- **[inventory/](./inventory/)** — current state as data: `services.yml`,
  `domains.yml`, `mail-aliases.yml`
- **[scripts/](./scripts/)** — local bash scripts wrapping SSH to actually
  make changes (nothing is installed on the droplet itself)

Start at [docs/connecting.md](./docs/connecting.md).
