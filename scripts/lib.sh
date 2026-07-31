#!/usr/bin/env bash
# Shared config for every script in this directory. Source it, don't run it.
set -euo pipefail

DROPLET_HOST="root@165.22.16.160"   # migrated from 142.93.166.76, see ADR-0008
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES_YML="$REPO_ROOT/inventory/services.yml"

ssh_run() {
  ssh "${SSH_OPTS[@]}" "$DROPLET_HOST" "$1"
}

scp_to_droplet() {
  local local_path="$1" remote_path="$2"
  scp "${SSH_OPTS[@]}" "$local_path" "$DROPLET_HOST:$remote_path"
}

# Prints the current next_free_port value from inventory/services.yml.
# No yq/pyyaml available on this machine — the file's format is deliberately
# simple (one scalar per line) so grep/sed is enough. If services.yml ever
# grows past what this can handle, switch to yq.
next_free_port() {
  grep -m1 '^next_free_port:' "$SERVICES_YML" | sed -E 's/^next_free_port:[[:space:]]*([0-9]+).*/\1/'
}

# Bumps next_free_port to the given value in-place.
set_next_free_port() {
  local new_port="$1"
  sed -i.bak -E "s/^next_free_port:.*/next_free_port: $new_port/" "$SERVICES_YML"
  rm -f "$SERVICES_YML.bak"
}
