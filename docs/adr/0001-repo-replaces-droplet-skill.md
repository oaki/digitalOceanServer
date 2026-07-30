# Infra lives in this git repo, not in the Claude skill

The `droplet` Claude Code skill (`~/.claude/skills/droplet/skill.md`) previously
held all procedural knowledge for managing the droplet as prose, with no
structured record of current state (services, domains, ports, mail). We moved
that knowledge into this repo (`docs/`, `inventory/`, `scripts/`) and reduced
the skill to a stub that points here, because a skill file isn't version
controlled per-change, can't be diffed against actual droplet state, and isn't
somewhere a human would think to look for "what's actually running."
