# Adding a mail alias (relay-only forwarding)

See CONTEXT.md "Mail Alias" and `docs/adr/0003-mail-relay-only-no-mailboxes.md`
— this droplet forwards mail, it never stores it. Check
`inventory/mail-aliases.yml`'s `postfix_installed` flag before starting —
Postfix was installed 2026-07-31 for `siebi.sk`'s alias, so it's likely
already there; if `postfix_installed: true`, skip step 1 and go straight to
step 3.

**Before setting up a Postfix relay for a domain, check whether it already
has working mail hosting elsewhere first** (MX records pointing at a real
provider, e.g. Websupport) — creating a mailbox/alias through that existing
provider's own control panel is usually simpler and has better out-of-the-box
deliverability (SPF/DKIM/DMARC already configured) than this droplet's relay.
Only use this droplet's Postfix when there's no existing provider, or (as
with `siebi.sk`) the existing provider's mail feature requires a paid
plan/add-on the owner doesn't want and DNS can be safely repointed instead.

## Step 1 — Install Postfix (first alias only)

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "DEBIAN_FRONTEND=noninteractive apt-get install -y postfix"
```
Configure it for "Internet Site", hostname `chess-analysis.com` (or whatever
the primary domain is) when prompted — the `DEBIAN_FRONTEND=noninteractive`
flag above uses defaults; if it needs the mail_name set explicitly, use
`debconf-set-selections` first, then reinstall/reconfigure.

## Step 2 — Configure virtual alias forwarding (first alias only)

Add to `/etc/postfix/main.cf`:
```
virtual_alias_domains = siebi.sk
virtual_alias_maps = hash:/etc/postfix/virtual
```
Every subsequent domain gets appended to `virtual_alias_domains`
(space-separated).

## Step 3 — Add the alias mapping

Append a line to `/etc/postfix/virtual`:
```
info@siebi.sk    pavolbincik@gmail.com
```
Then:
```bash
postmap /etc/postfix/virtual && systemctl reload postfix
```

## Step 4 — Required DNS records (owner adds these manually)

For **each domain** used in a Mail Alias, at the registrar:
```
Type: MX     Name: @         Value: DOMAIN (or a real mail-capable host), priority 10
Type: TXT    Name: @         Value: "v=spf1 ip4:165.22.16.160 ~all"
```
Without the SPF record, mail forwarded *from* the droplet on this domain's
behalf is likely to be spam-flagged or rejected by the destination provider
(Gmail etc.) — this is not optional, it's required for the forward to
actually land in the inbox. DKIM can be added later for stronger
deliverability but isn't required to get forwarding working.

## Step 5 — Update inventory

Append to `inventory/mail-aliases.yml`:
```yaml
- address: info@siebi.sk
  forwards_to: pavolbincik@gmail.com
  domain: siebi.sk
  spf_record_added: true   # only after the owner confirms it's live
```
Set `postfix_installed: true` and `postfix_active: true` if this was the
first alias.

## Verifying

```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@165.22.16.160 "postfix check && systemctl is-active postfix"
```
Then send a real test email to the alias and confirm it arrives at the
forwarding target.
