#!/usr/bin/env bash
# Add a Postfix relay-only forwarding alias. See docs/mail-alias.md — this
# installs Postfix on first use, otherwise just appends a mapping.
# Usage: scripts/add-mail-alias.sh alias@domain.tld forward-target@example.com
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

ALIAS="${1:?usage: add-mail-alias.sh alias@domain.tld forward-target@example.com}"
FORWARD_TO="${2:?usage: add-mail-alias.sh alias@domain.tld forward-target@example.com}"
DOMAIN="${ALIAS#*@}"

echo "==> Checking whether postfix is installed"
if ssh_run "dpkg -s postfix >/dev/null 2>&1"; then
  echo "    postfix already installed"
else
  echo "==> Installing postfix (first alias ever) — 'Internet Site' config, non-interactive"
  ssh_run "DEBIAN_FRONTEND=noninteractive apt-get install -y postfix"
fi

echo "==> Ensuring $DOMAIN is in virtual_alias_domains"
ssh_run "postconf virtual_alias_domains 2>/dev/null | grep -qw '$DOMAIN' || postconf -e \"virtual_alias_domains = \$(postconf -h virtual_alias_domains 2>/dev/null) $DOMAIN\""
ssh_run "postconf -h virtual_alias_maps 2>/dev/null | grep -q hash:/etc/postfix/virtual || postconf -e 'virtual_alias_maps = hash:/etc/postfix/virtual'"

echo "==> Appending alias mapping"
ssh_run "grep -qF '$ALIAS' /etc/postfix/virtual 2>/dev/null || echo '$ALIAS    $FORWARD_TO' >> /etc/postfix/virtual"
ssh_run "postmap /etc/postfix/virtual && systemctl restart postfix"

cat <<EOF
==> Done. REQUIRED before mail will deliver reliably — add these DNS records
    for $DOMAIN manually (see docs/mail-alias.md step 4):

  Type: MX     Name: @    Value: $DOMAIN (or a real mail host), priority 10
  Type: TXT    Name: @    Value: "v=spf1 ip4:142.93.166.76 ~all"

==> Then add to inventory/mail-aliases.yml:

  - address: $ALIAS
    forwards_to: $FORWARD_TO
    domain: $DOMAIN
    spf_record_added: false   # flip to true once the TXT record is confirmed live
EOF
