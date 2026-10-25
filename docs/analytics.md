# Web analytics (Umami)

One self-hosted [Umami](https://umami.is) instance collects analytics for
every site: **https://analytics.saniolabs.com**. Each site gets its own
website profile in it. Why it is built and run this way:
`docs/adr/0012-self-hosted-umami-built-locally.md`.

| What | Where |
|---|---|
| Service | PM2 process `umami`, `127.0.0.1:3009`, Node 24 |
| Code | `/opt/apps/umami/current` -> `releases/<tag>` (previous release kept) |
| Config | `/opt/apps/umami/.env` (mode 600), PM2 file `/opt/apps/umami/ecosystem.config.cjs` |
| Database | local PostgreSQL 16, database and role `umami` |
| nginx | `/etc/nginx/sites-enabled/analytics.saniolabs.com` (copy in `nginx/`) |
| Admin login | user `admin`, password in `/opt/apps/umami/.admin-password` |
| API key | `/opt/apps/umami/.api-key`, used only by `scripts/add-analytics-site.sh` |
| Tracked sites | `inventory/analytics.yml` |

Read the admin password without printing it into a shared log:

```bash
ssh -i ~/.ssh/id_ed25519 root@165.22.16.160 "cat /opt/apps/umami/.admin-password" | pbcopy
```

## Add analytics to a site

1. **Create the profile** (idempotent, safe to re-run):
   ```bash
   scripts/add-analytics-site.sh chess-analysis.com "Chess Analysis"
   ```
   Prints the website id, the dashboard link and the tag, for example:
   ```html
   <script defer src="https://analytics.saniolabs.com/script.js" data-website-id="..." data-domains="chess-analysis.com,www.chess-analysis.com"></script>
   ```
   `data-domains` makes the tracker ignore every other hostname (localhost,
   previews), so the tag ships unconditionally. Page views in client-side
   routed apps (Next.js, React Router) are tracked automatically.
2. **Put the tag into the site's source repo**, once, in the shared layout
   (see the next section). Never edit built files on the droplet: the next
   deploy overwrites them.
3. **Content-Security-Policy:** if the site sends one, add
   `https://analytics.saniolabs.com` to `script-src` and `connect-src`.
   Otherwise the browser blocks the tracker without any visible error.
4. **Deploy** the site through its normal pipeline.
5. **Verify** (next sections), then replace `snippet_in: TODO` in
   `inventory/analytics.yml` with `repo:path/to/file`.

### Where the snippet goes

| Stack | File | Form |
|---|---|---|
| Next.js App Router (also `output: 'export'`) | root `app/layout.tsx` | `import Script from 'next/script'` and `<Script src="..." data-website-id="..." data-domains="..." strategy="afterInteractive" />` |
| Next.js Pages Router | `pages/_document.tsx`, inside `<Head>` | plain `<script defer ...>` |
| Vite, CRA, any SPA | `index.html`, inside `<head>` | plain tag |
| Astro | base layout `<head>` | `<script is:inline defer ...>` |
| Nuxt | `nuxt.config.ts` -> `app.head.script` | `{ src, defer: true, 'data-website-id': ..., 'data-domains': ... }` |
| Laravel | main Blade layout `<head>` | plain tag |
| Plain PHP | shared header include | plain tag |
| Static multi-page HTML | shared partial; if none, every page's `<head>` | plain tag |

### Verify

```bash
# 1. The live HTML carries the tag (static export / SSR pages):
curl -s https://DOMAIN/ | grep -o 'data-website-id="[^"]*"'
# 2. The tracker is reachable:
curl -sI https://analytics.saniolabs.com/script.js | head -1
```

Then open the site in a browser without an ad blocker and watch the
dashboard's realtime view, or ask the API for active visitors:

```bash
ssh -i ~/.ssh/id_ed25519 root@165.22.16.160 'curl -s -H "Authorization: Bearer $(cat /opt/apps/umami/.api-key)" http://127.0.0.1:3009/api/websites/WEBSITE_ID/active'
```

### Reading stats

Totals for the last 7 days (`startAt`/`endAt` are Unix milliseconds):

```bash
ssh -i ~/.ssh/id_ed25519 root@165.22.16.160 'end=$(date +%s000); start=$((end - 7*86400000)); curl -s -H "Authorization: Bearer $(cat /opt/apps/umami/.api-key)" "http://127.0.0.1:3009/api/websites/WEBSITE_ID/stats?startAt=$start&endAt=$end"'
```

## Upgrading Umami

```bash
scripts/deploy-umami.sh v3.5.0
```

Needs the local Docker daemon running. Builds the tag in a `linux/amd64`
container, uploads it, runs database migrations, switches `current`, health
checks `/api/heartbeat` and rolls the symlink back if that fails. Read the
release notes first: migrations run forward only, and rolling the code back
does not roll the schema back.

## One-time setup (done 2026-10-25, for a rebuild from scratch)

1. PostgreSQL role and database `umami` with a random password; `.env` in
   `/opt/apps/umami/` with `DATABASE_URL`, a random `APP_SECRET`,
   `CLIENT_IP_HEADER=x-real-ip` (nginx overwrites that header, so visitors
   cannot spoof their IP) and `DISABLE_TELEMETRY=1`.
2. `scripts/deploy-umami.sh <tag>` - the first run creates the tables and
   the default `admin` / `umami` account.
3. Replace the default password at once: log in through
   `POST /api/auth/login` on `127.0.0.1:3009`, call `POST /api/me/password`
   with a random password, store it in `.admin-password` (mode 600).
4. Create the API key for the script with `POST /api/me/api-keys`
   (`{"name": "add-analytics-site"}`) and store the returned `key` in
   `.api-key` (mode 600). It is shown only once. API keys cannot reach
   `/api/users`, `/api/admin`, `/api/auth` or password routes.
5. DNS: A record `analytics` -> `165.22.16.160` at Websupport (owner adds it
   manually, see ADR-0002).
6. nginx: port-80 vhost proxying to `127.0.0.1:3009`, then
   `certbot --nginx -d analytics.saniolabs.com --redirect`, then `http2`
   on the 443 listener. The result is `nginx/analytics.saniolabs.com.conf`.

## Known limits

- Ad blockers with privacy lists may block part of the traffic. If the gap
  matters, add a neutral hostname and set `TRACKER_SCRIPT_NAME` and
  `COLLECT_API_ENDPOINT` in `.env`; both work at runtime in this build.
- The droplet has 2 GB RAM and little headroom. `pm2 monit` or
  `scripts/status.sh` shows `umami` memory; PM2 restarts it above 400 MB.
