# Deploying a new PHP site

A **PHP Site** (see CONTEXT.md) is git-deployed like a Static Site, but
requests for `.php` files are handed to PHP-FPM instead of being served as
static files. See `docs/adr/0007-php-via-ondrej-ppa-shared-fpm-pool.md` for
why PHP 8.3 / the ondrej PPA / a shared pool. Use `scripts/add-php-site.sh`
rather than doing this by hand.

## Prerequisites (one-time, already done on the current droplet)

```bash
add-apt-repository -y ppa:ondrej/php
apt-get update
apt-get install -y php8.3-fpm php8.3-cli php8.3-common php8.3-mysql \
  php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip php8.3-gd php8.3-bcmath php8.3-intl
systemctl enable --now php8.3-fpm
```
This only needs repeating on a droplet that doesn't have PHP yet — check
`inventory/services.yml`'s `php_installed` flag first. **Only works on
Ubuntu 22.04/24.04 (jammy/noble)** — the PPA publishes nothing for older
releases; re-verify before using this on any other droplet.

## Steps for a new site

1. **Clone the repo** into `/opt/apps/SITE_NAME` (git pull —r a build step only
   if the project needs one, e.g. `composer install` for a Composer-based app).
2. **nginx vhost** — static files served directly, `.php` requests handed to
   the shared FPM pool over its Unix socket:
   ```nginx
   server {
       server_name DOMAIN;
       root /opt/apps/SITE_NAME;
       index index.php index.html;

       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }

       location ~ \.php$ {
           include snippets/fastcgi-php.conf;
           fastcgi_pass unix:/run/php/php8.3-fpm.sock;
       }

       listen 80;
   }
   ```
   then `nginx -t && systemctl reload nginx`.
3. **Certbot:**
   ```bash
   certbot --nginx -d DOMAIN --non-interactive --agree-tos --email pavolbincik@gmail.com
   ```
4. **Env vars / secrets** — same convention as Node services: a `.env` or
   framework-specific config file lives only on the droplet, never in git.
   Track key *names* (not values) in `inventory/services.yml`'s `php_sites`
   list.
5. **Update inventory** — append to `php_sites` in `inventory/services.yml`.

## When a site needs its own FPM pool instead of the shared one

Copy `/etc/php/8.3/fpm/pool.d/www.conf` to a new file (e.g. `sitename.conf`),
change its `[pool-name]` header and `listen = /run/php/php8.3-fpm-SITENAME.sock`,
then point that site's nginx `fastcgi_pass` at the new socket path. Reasons to
do this: the site needs different `php.ini` settings, its own resource limits,
or genuine isolation from other PHP sites. Restart `php8.3-fpm` after adding
a pool file.

## Laravel (or other Composer-based) sites

A framework app needs more than the plain steps above:

1. `composer install --no-dev --optimize-autoloader` (use `COMPOSER_ALLOW_SUPERUSER=1` since we run as root) — **check the PHP version composer.lock actually needs first**: `composer.json`'s `require.php` may say `^8.3`, but the *locked* package versions can require newer (e.g. siebi.sk's Symfony 8.1 packages need PHP 8.4+ even though its composer.json allows 8.3). If the shared pool's PHP version doesn't satisfy the lockfile, install the newer PHP version and give the site its own dedicated pool (copy `www.conf`, rename the pool + `listen` socket path) rather than upgrading the shared pool for everyone.
2. `cp .env.example .env`, then set `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://DOMAIN`.
3. `php{VERSION} artisan key:generate --force`
4. If `DB_CONNECTION=sqlite`: `touch database/database.sqlite` before migrating. Otherwise provision whatever DB it needs first.
5. `php{VERSION} artisan migrate --force`
6. `npm install && npm run build` if there's a `vite.config.js`/frontend build step.
7. `chown -R www-data:www-data storage bootstrap/cache database && chmod -R 775 storage bootstrap/cache` — PHP-FPM runs as `www-data` and needs to write there.
8. nginx `root` points at `public/` (Laravel's actual document root), not the project root:
   ```nginx
   location / {
       try_files $uri $uri/ /index.php?$query_string;
   }
   location ~ \.php$ {
       include snippets/fastcgi-php.conf;
       fastcgi_pass unix:/run/php/POOL_SOCKET;
   }
   location ~ /\.(?!well-known).* {
       deny all;
   }
   ```

## Verifying

```bash
curl -s -o /dev/null -w '%{http_code}' https://DOMAIN/
systemctl is-active php8.3-fpm
```
