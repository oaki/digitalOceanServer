# Zálohy VPS

Nočná záloha beží na VPS (`/usr/local/sbin/vps-backup.sh`, cron `/etc/cron.d/vps-backup`, 03:15 UTC, log `/var/log/vps-backup.log`).

| Čo | Ako |
|---|---|
| Databázy | `pg_dump -Fc` každej databázy okrem `postgres`, dynamicky (nové databázy sa pridajú samy) |
| Konfigurácia | tar: `/etc/nginx`, `/etc/letsencrypt`, `/etc/postfix`, `/etc/livekit`, `/etc/baromio-probe`, `/root/.pm2/dump.pm2`, redis.conf, `/opt/apps/*/.env`, `pm2-*.json`, `*.config.cjs`, deploy skripty, `authorized_keys`, root crontab |
| Šifrovanie | `age`, na serveri je len verejný kľúč (`/root/.config/r2/age_recipient.txt`) |
| Úložisko | lokálne `/var/backups/vps/` 7 dní, Cloudflare R2 bucket `vps-backups` 30 dní |
| Prístup do R2 | účtový token `vps-backups-writer` (Object Read & Write, len bucket `vps-backups`, povolená len IPv4 `187.7.19.10`); kľúče v `/root/.config/r2/` (root, 600) |

**Súkromný `age` kľúč** je len na Macu vlastníka: `~/.config/vps-backup-age/key.txt`. Bez neho sa zálohy nedajú obnoviť. Uložiť kópiu do správcu hesiel.

IPv4: token je obmedzený na IPv4 adresu VPS, preto `/etc/gai.conf` uprednostňuje IPv4 a skript nastavuje `GODEBUG=netdns=cgo` (rclone 1.60 z Ubuntu inak spojenie vedie cez IPv6 a R2 odmietne s 403).

## Obnova

```bash
# stiahnuť na VPS (rclone s R2 env premennými ako v skripte) a odšifrovať na Macu
age -d -i ~/.config/vps-backup-age/key.txt pg_<db>_<čas>.dump.age > db.dump
pg_restore --clean --if-exists --no-owner -d <db> db.dump
```

Overené 2026-11-20: dump `videocall` z R2 sa odšifroval kľúčom z Macu a je platný PostgreSQL dump (v1.15). Plný restore do dočasnej databázy sa urobí pred vypnutím Droplet (plán, Fáza 5, bod 4).
