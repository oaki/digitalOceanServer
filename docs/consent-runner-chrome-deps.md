# Chrome library dependencies for the Consent Runner

`pulseGuard/docs/design-plans/2026-09-24-consent-scan.md` (line 885) says the Chrome library
packages were "recorded by the spike (40 packages)" — that list does not actually exist
anywhere in the `pulseGuard` repo (checked `workers/consent-spike/` directly). Recorded here
instead, determined fresh on 2026-09-25 against `chrome-headless-shell@127.0.6533.88` (the
build pinned by `puppeteer-core@22.15.0`, from
`node_modules/puppeteer-core/lib/esm/puppeteer/revisions.js`), on the droplet itself
(Ubuntu 24.04 noble).

## How it was determined

```bash
ldd /opt/consent-runner/.cache/chrome-headless-shell/linux-127.0.6533.88/chrome-headless-shell-linux64/chrome-headless-shell \
  | grep 'not found'
```

Most of Chrome's shared-library dependencies were already satisfied on this droplet (X11,
glib, nss, dbus, etc. — pulled in by other installed software). Only 9 were actually missing;
installing them pulled in their own transitive dependencies automatically via apt, so no
larger curated 40-package list was needed here — `ldd` against the real binary is the
authoritative check, not a fixed package list carried over from another host.

## Packages installed (2026-09-25)

```bash
apt-get install -y \
  libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
  libgbm1 libasound2t64
```

| Missing symbol (`ldd` output) | Package |
|---|---|
| `libatk-1.0.so.0` | `libatk1.0-0t64` |
| `libatk-bridge-2.0.so.0` | `libatk-bridge2.0-0t64` |
| `libatspi.so.0` | `libatspi2.0-0t64` |
| `libXcomposite.so.1` | `libxcomposite1` |
| `libXdamage.so.1` | `libxdamage1` |
| `libXfixes.so.3` | `libxfixes3` |
| `libXrandr.so.2` | `libxrandr2` |
| `libgbm.so.1` | `libgbm1` |
| `libasound.so.2` | `libasound2t64` |

(Ubuntu 24.04 renamed several packages with a `t64` suffix for the 64-bit `time_t` transition
— `libatk1.0-0`, `libatk-bridge2.0-0` and `libasound2` from older guides no longer exist under
those names on noble.)

`unzip` was also missing (needed by `puppeteer browsers install` to extract the downloaded
archive, unrelated to Chrome's own runtime deps) — installed separately.

After installing these 9, `ldd` against the binary reported zero missing libraries, and
`chrome-headless-shell --headless --disable-gpu --no-sandbox --dump-dom about:blank` rendered
successfully.

## If Chrome is upgraded later

Re-run the `ldd` check above against whatever build id `puppeteer-core`'s pinned revision
resolves to at the time — don't assume this exact list still holds for a different Chrome
version.
