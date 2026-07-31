# Auto-deploy uses a dedicated, command-restricted SSH key — not the main root key

`siebi.sk` auto-deploys on push to `main` via a GitHub Actions workflow
(`.github/workflows/deploy.yml` in that repo) that SSHs into the droplet.
Rather than putting the main `~/.ssh/id_ed25519` private key (full root
access to everything on the droplet) into that repo's GitHub Actions
secrets, we generated a **dedicated keypair** for this one purpose and
restricted it in the droplet's `authorized_keys` with `command=`, forcing
it to only ever run `/opt/apps/siebi.sk-deploy.sh` regardless of what the
SSH client requests — verified directly (an attempt to run an arbitrary
command through this key was silently ignored, only the forced script ran).

This means a compromised GitHub Actions secret (leaked token, malicious
workflow injected via a compromised dependency, etc.) can at worst trigger
a redeploy of `siebi.sk` — not read other services' `.env` secrets, not
touch other sites, not do anything else root can do. The cost is a little
more setup per repo (a new keypair + `authorized_keys` line + a small
deploy script) instead of reusing one key everywhere — worth it given
GitHub Actions secrets are a meaningfully different trust boundary (CI
infrastructure, third-party actions) than this repo's own scripts.

Same pattern to follow for any other repo that gets auto-deploy later: new
dedicated key, its own forced command, its own deploy script.
