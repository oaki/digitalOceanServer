# Automation scripts run on the control machine, not the droplet

`scripts/` are local bash scripts that shell out over SSH to make changes —
nothing from this repo is ever cloned onto the droplet itself. This follows
the standard single-server "control machine" pattern (as used by Ansible/
Fabric): the droplet stays minimal with no extra tooling to keep in sync with
git, no ops-repo checkout to update, and no additional attack surface. Since
there's exactly one droplet and one control point (this repo, run via Claude
or directly by the owner), there's no benefit to also installing the scripts
server-side.
