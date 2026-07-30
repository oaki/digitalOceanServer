# Mail is relay-only: Postfix forwarding, no local mailboxes

The droplet runs Postfix configured only for `virtual_alias_maps` — mail
arriving for an address like `info@siebi.sk` is immediately forwarded to an
external mailbox (e.g. Gmail) and not stored. There is no Dovecot, no IMAP, and
no mailbox a mail client could connect to directly on the droplet. We chose
this over a full mail server because self-hosting inbound+outbound mail with
local storage on a single small droplet is fragile in practice (deliverability,
spam-blacklisting of the droplet's IP, no control over reverse DNS) — DO itself
discourages it. Forwarding still requires SPF/DKIM records for the source
domain naming the droplet's IP as a permitted sender, or the forwarded copy
gets spam-flagged at the destination; see `docs/mail-alias.md`.
