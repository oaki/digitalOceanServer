# Plán migrácie: Droplet na VPS

Presun všetkého z Droplet (`165.22.16.160`, 1 vCPU, 2 GB RAM) na VPS (`187.7.19.10`, Hostinger, 4 vCPU, 15 GB RAM, 193 GB disk). Rozhodnutia a ich dôvody: [ADR-0013](adr/0013-migrate-droplet-to-hostinger-vps.md). Pojmy: [CONTEXT.md](../CONTEXT.md) (VPS, Droplet, Cutover).

Stav plánu: navrhnutý 2026-11-20, nič z neho sa zatiaľ nevykonalo. VPS je čistý Ubuntu 26.04.1 (len `sshd`, Monarx, bez firewallu, `/opt` prázdny).

## Rozhodnutia v skratke

| Téma | Rozhodnutie |
|---|---|
| OS | Ubuntu 26.04 (zostáva, bez reinštalácie na 24.04) |
| PostgreSQL | 16 z PGDG (rovnaká hlavná verzia ako na Droplet) |
| PHP | 8.4 z ondrej PPA (vetva `resolute` existuje) |
| Cutover | Postupne po službách, DNS po jednej doméne, Droplet ostáva nedotknutý ako rollback |
| CI | Vo workflow sa zmení IP na `187.7.19.10` pri Cutoveri daného repa |
| Certifikáty | Kópia `/etc/letsencrypt` z Droplet pred Cutoverom |
| Zálohy | Nočný `pg_dump` + konfigurácia, šifrované `age`, do Cloudflare R2 |
| Neprenáša sa | v2 (`server`, `worker1`, blue/green), Node 14, `chess-analysis-gui` |
| Prenáša sa navyše | `baromio-probe`; `consent-runner` ako voliteľný krok na konci |
| Poistka | Droplet beží 7 dní po poslednom Cutoveri, potom sa zmaže |

## Čo sa prenáša

| Skupina | Položky |
|---|---|
| PM2 Services | `v3-api`, `v3-worker`, `english-together`, `memory-puzzle-game`, `personal-api`, `pulseguard-ping-worker`, `pulseguard-uptime-worker`, `umami`, `videocall-api`, `videocall-web` |
| Static Sites | `contexthub`, `abakus`, `saskamath`, `chess-analysis-v3-web` (www a apex `chess-analysis.com`) |
| PHP Site | `siebi.sk` (Laravel, PHP 8.4, SQLite súbor) |
| systemd | `videocall-livekit`, `baromio-probe`, `consent-runner` (voliteľne) |
| Databázy | `chess_v3` (1,3 GB), `umami`, `english_together` (rola `english_together_app`), `videocall`; len `umami` má rozšírenie `pgcrypto` |
| Iné | Redis (64 MB, `allkeys-lru`, používa `personal-api`), Postfix relay pre `siebi.sk`, nginx catch-all, cron `english-together-voice-limit` (každú minútu), cron `chess-sync-computer-release.sh` (každých 10 minút) |
| Dáta | Syzygy 940 MB, Stockfish 19 (`/opt/stockfish`), `/opt/data/chess-analysis` (`book_new.bin`), `/opt/apps/computer-releases` (znovu stiahnuteľné cez sync), `/opt/chess-analysis-imports` (voliteľné, zdrojové knihy sú aj v repe v3) |

## Fáza 1: základ VPS

1. Nastaviť hostname, časovú zónu `Europe/Bratislava`, `chrony` už beží.
2. `ufw`: povoliť `22/tcp`, `80/tcp`, `443/tcp`, `25/tcp`, `7881/tcp`, `7882/udp`, `3478/udp`, `5349/tcp`, `30000:40000/udp` (rovnaká sada ako na Droplet, aj pre IPv6). Skontrolovať aj sieťový firewall v paneli Hostingera, ak je zapnutý.
3. SSH: iba kľúč (`PasswordAuthentication no`), root zostáva (skripty a CI používajú `root@`). Pridať kľúče z `~/.ssh/authorized_keys` Droplet vrátane 10 záznamov s `command=` až pri príslušnom Cutoveri.
4. `unattended-upgrades`, `sysstat`, `fail2ban` (voliteľné). Monarx agent (nainštaloval Hostinger) ostáva, sleduj jeho spotrebu.
5. Swap 2 GB ako poistka (VPS dnes nemá swap).
6. Postfix `myhostname` nastaviť na FQDN VPS (reverzný záznam IP je `srv2181267.hstgr.cloud`).

## Fáza 2: softvér

| Čo | Ako |
|---|---|
| nginx, certbot + `python3-certbot-nginx`, git, redis-server, postfix, age, sysstat, mariadb-client-core | `apt` z archívu 26.04 |
| PostgreSQL 16 | PGDG repozitár (`resolute-pgdg`), balík `postgresql-16`; `shared_buffers` a `max_connections` ladiť až po migrácii |
| PHP 8.4 | ondrej PPA, `php8.4-fpm` + `cli`, `mbstring`, `xml`, `curl`, `gd`, `intl`, `mysql`, `sqlite3`, `bcmath`, `zip`; `composer`; pool `siebi.conf` skopírovať z Droplet |
| Node | `nvm`, Node 24.18.1 (rovnaká verzia ako na Droplet), `pm2@7.0.3`, `corepack` (pnpm); `pm2 startup` s `PATH` obsahujúcim nvm bin |
| LiveKit | binárka `livekit-server` 1.13.7 do `/usr/local/bin`, používateľ `livekit`, `/etc/sysctl.d/99-livekit.conf` (rmem/wmem 5000000) |
| Stockfish 19 | `/opt/stockfish/19` + symlink `current`, binárku skopírovať z Droplet (apt má len 17) |
| Chrome headless-shell | Až pri voliteľnom kroku `consent-runner`, závislosti podľa `docs/consent-runner-chrome-deps.md` |

Node 14 a PHP 8.3 sa neinštalujú.

## Fáza 3: konfigurácia a tajomstvá bez DNS zmeny

Všetko sa kopíruje priamo medzi serverami (`scp -3` alebo `rsync` cez dočasný kľúč). Obsah súborov s tajomstvami nesmie prejsť cez konverzáciu ani commit.

1. `/etc/letsencrypt` (certifikáty, `renewal/`, `renewal-hooks/deploy/renew-videocall-livekit-cert`). Po prvom Cutoveri overiť `certbot renew --dry-run` z VPS.
2. nginx: `nginx.conf` (gzip), `snippets/`, vhosty zo `sites-available`, catch-all, `/opt/nginx-default`. Vynechať vhost `api.chess-analysis.com` a `/etc/nginx/chess-analysis-api-active.conf` (v2 sa neprenáša).
3. `.env` súbory každej služby, `ecosystem.config.cjs` súbory (`umami`, `chess-analysis-v3`, `english-together-runtime`, `memory-puzzle-game-runtime`), `/etc/livekit/livekit.yaml`, `/etc/baromio-probe/env`.
4. `~/.ssh` (deploy kľúče GitHubu `*_deploy` a `config` s aliasmi `github-*`). Rovnaké kľúče sa znovu použijú, GitHub ich akceptuje z oboch serverov.
5. `authorized_keys` s `command=` obmedzeniami pre CI (po Cutoveri každého repa), deploy skripty `/opt/apps/*-deploy.sh`.
6. Dáta: Syzygy, `/opt/stockfish`, `/opt/data/chess-analysis`, `computer-releases` sync cron.
7. Zálohy do Cloudflare R2 sa nastavia pred prvým Cutoverom s databázou: bucket, token len na zápis do jedného bucketu, `age` verejný kľúč na serveri, súkromný kľúč u teba. Nočný `pg_dump` všetkých štyroch databáz + tar konfigurácie (`/etc/nginx`, `/etc/letsencrypt`, `/etc/postfix`, `/etc/livekit`, `/opt/apps/*/.env`); 7 dní lokálne, 30 dní v R2. Pred prvou produkčnou databázou urobiť testovací restore.

## Fáza 4: Cutover po službách

Postup pre každú službu, rovnaký:

1. Nasadiť na VPS (klon, build alebo kópia release, `pm2 start`, `pm2 save`).
2. Overiť cez `curl --resolve DOMENA:443:187.7.19.10 https://DOMENA/` (certifikát je už skopírovaný).
3. Ak má služba databázu: zmraziť zápisy na Droplet (`pm2 stop`), `pg_dump | pg_restore` alebo kópia SQLite, porovnať počty riadkov.
4. Prepnúť DNS záznam na `187.7.19.10` (manuálne, ADR-0002; TTL je už 300 s).
5. Overiť zvonku (HTTPS, redirect z HTTP, funkčné jadro služby).
6. CI repa: IP vo workflow na `187.7.19.10`, nový `DEPLOY_KNOWN_HOSTS` (výstup `ssh-keyscan` pre VPS), spustiť nasadenie.
7. Na Droplet službu nechať zastavenú (nemazať), aktualizovať `inventory/`.

Rollback: DNS späť na `165.22.16.160`, `pm2 start` na Droplet. Ak medzitým písala do databázy VPS, dump sa vráti opačným smerom.

**Dôležité pre `*.chess-analysis.com`:** apex a subdomény idú cez wildcard v DNS na DigitalOcean (`v3.chess-analysis.com` nemá vlastný záznam). Aby sa dali prepínať po jednom, pred Cutoverom pridať **explicitný A záznam** pre každú subdoménu; explicitný záznam má prednosť pred wildcardom. Wildcard sa prepne až na konci.

### Vlny

| Vlna | Služby | Poznámky |
|---|---|---|
| 1 | `contexthub.uk`, `abakus.contexthub.uk`, `math.contexthub.uk` (statické, CI) | Bez dát, najlepší prvý test celého postupu vrátane CI a certifikátu. |
| 2 | `pulseguard-ping-worker`, `pulseguard-uptime-worker` (vlastné explicitné DNS záznamy, sparse checkout `/opt/pulseGuard-monorepo`, `CROSS_CHECK_PSK`) | Bezstavové; očakávaná odpoveď zvonku je 401. |
| 3 | `personal-api` (`api.contexthub.uk`, Redis), `memory-puzzle-game` (Websupport MySQL), `umami` (`analytics.saniolabs.com`, PG), `english-together` (PG + cron voice-limit + releases) | **Najprv povoliť IP `187.7.19.10` vo Websupport** pre MySQL (Droplet sa tam dnes pripája). Umami: tracker sa nemení, doména `analytics.saniolabs.com` ostáva rovnaká. |
| 4 | v3: `v3-api`, `v3-worker`, `chess-analysis-v3-web`, `v3.chess-analysis.com`, www + apex | Prepínajú sa spolu (API a worker idú cez `127.0.0.1:3007`). `chess_v3` 1,3 GB: dump a restore s `nice/ionice`. Na 4 vCPU zvážiť `THREADS` (dnes 1) a `HASH_MB` (dnes 64), ale až po stabilizácii. Worker je v DB zaregistrovaný ako `droplet-1`. |
| 5 | `call.contexthub.uk`: `videocall-api`, `videocall-web`, `videocall-livekit`, DB `videocall` | Najcitlivejšia vlna (verejné UDP porty, TURN). Cutover mimo hovorov. Certifikát pre LiveKit nainštaluje deploy hook, ktorý sa skopíroval s `/etc/letsencrypt`. Overiť hovor medzi dvoma zariadeniami. |
| 6 | `siebi.sk` + mail: PHP 8.4 pool, `database.sqlite`, Postfix `virtual_alias_domains` | Najprv overiť príjem na porte 25 zvonku (odchádzajúci port 25 už overený). Pri Cutoveri odstrániť zastaraný `AAAA` záznam `2a03:b0c0:...` z DNS (patrí DigitalOcean) alebo ho nahradiť IPv6 adresou VPS. SPF `v=spf1 mx -all` a MX ostávajú logicky rovnaké. Test: mail na `info@siebi.sk` dorazí do Gmailu. |
| 7 | `baromio-probe` | V `/etc/baromio-probe/env` je `BAROMIO_ALLOW` s IP Droplet, zmeniť na IP VPS. Pozorovacie stanovisko sa zmení z DigitalOcean Frankfurt na Hostinger, over na strane Baromio. |
| 8 (voliteľné) | `consent-runner` | Vypnutý od 2026-11-02. Zmeniť `IPAddressDeny` (vlastná verejná IP) v unite, na 26.04 vyriešiť AppArmor profil pre user namespaces. Ak sa nepoužíva, len archivovať unit a `/etc/consent-runner.env`. |

## Fáza 5: dokončenie a vypnutie Droplet

1. Prepnúť wildcard `*.chess-analysis.com` na VPS a odstrániť záznam `api.chess-analysis.com` (v2 sa neprenáša, dnes vracia 502).
2. Aktualizovať repo: `scripts/lib.sh` (`DROPLET_HOST` na VPS), `docs/connecting.md` a ďalších 9 súborov s IP, `inventory/*.yml`, `CONTEXT.md` (odstrániť heslo Droplet), `README.md`, doplniť ADR.
3. Počkať **7 dní** po poslednom Cutoveri. Počas nich sledovať: `pm2 list`, `certbot renew --dry-run`, nočnú zálohu do R2, logy nginx.
4. Overiť zálohu: restore najnovšieho dumpu `chess_v3` do dočasnej databázy.
5. Archív pred zmazaním, **lokálne** (nie na VPS), šifrovaný `age`: `/opt/apps/chess-analysis-api-blue`, `-green`, `chess-analysis-worker`, `chess-analysis-gui`, `consent-runner` unit a env, `.env` súbory (ak sa nepreniesli všetky).
6. Zmazať Droplet v DigitalOcean; DNS zóna `chess-analysis.com` na DO ostáva.

## Otvorené body (overiť pred príslušnou vlnou)

| Bod | Kedy | Ako |
|---|---|---|
| Websupport MySQL povoľuje pripojenie len z IP Droplet | Pred vlnou 3 | Pridať `187.7.19.10` v zákazníckej zóne Websupport |
| Príjem na porte 25 a firewall Hostingera pre UDP 30000-40000, 3478, 5349 | Pred vlnou 5 a 6 | Test zvonku po inštalácii |
| Vplyv novej IP na Baromio probe | Pred vlnou 7 | Over u Baromio |
| LiveKit API kľúč a tajomstvo sa pri tejto analýze zobrazili vo výpise terminálu | Pri vlne 5 | Vygenerovať nové a upraviť `livekit.yaml` a `videocall-api` `.env` |
| `NODE_ENV=development` v `personal-api` (pozn. v `services.yml`) | Vlna 3 | Potvrdiť, či má byť `production` |
| Reputácia IP Hostingera pre odchádzajúcu poštu (Gmail) | Vlna 6 | End-to-end test z Gmailu |
| Ladenie po migrácii (`shared_buffers`, `THREADS`, `HASH_MB`, limity umami) | Po vypnutí Droplet | Samostatný krok, nie súčasť migrácie |
