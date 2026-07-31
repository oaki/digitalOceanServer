#!/usr/bin/env bash
# Verify a domain's DNS is live and print the reminder for what to do next.
# This does NOT touch DNS itself (DNS is managed manually — see
# docs/adr/0002-manual-dns-management.md) and does NOT deploy anything —
# use scripts/add-service.sh or scripts/add-static-site.sh for that, both of
# which already check DNS before proceeding.
# Usage: scripts/add-domain.sh DOMAIN
set -euo pipefail

DOMAIN="${1:?usage: add-domain.sh DOMAIN}"

echo "==> Checking DNS for $DOMAIN"
resolved="$(dig +short "$DOMAIN" | tail -1)"
if [ "$resolved" = "165.22.16.160" ]; then
  echo "OK: $DOMAIN already resolves to 165.22.16.160."
  echo "Next: run add-service.sh or add-static-site.sh, then update inventory/domains.yml."
else
  echo "$DOMAIN resolves to '${resolved:-nothing}', not 165.22.16.160 yet."
  cat <<EOF

Add this record at wherever $DOMAIN's DNS is managed, then re-run this script:

  Type: A
  Name: @ (or the subdomain)
  Value: 165.22.16.160
EOF
fi
