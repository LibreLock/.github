<div align="center">
  <img src="../content/logo.svg" alt="LibreLock logo" height="60" />
  <h1 align="center">Self-Hosting LibreLock</h1>
</div>

Running LibreLock on your own machine or server. Everything here uses the stack file in this repository - one Compose project with two containers:

| Container | What it does |
| --- | --- |
| `web` | Serves the app and proxies `/api` to the API. This is the only container with a published port |
| `api` | Go server + embedded SQLite database, on a private network, not reachable from outside |

Because the API is proxied under `/api` on the same origin as the app, there is no CORS to configure, no second port to open, and the session cookie stays first-party.

## Requirements

- Docker 23 or newer with the Compose plugin, on `linux/amd64` or `linux/arm64` - both are published,so a Raspberry Pi or an ARM VPS works
- Not much else: the two containers idle in well under 200 MB
- For anything other than `localhost`: a domain and HTTPS (see [HTTPS is required](#https-is-required))

## Quick start

```bash
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/compose.yaml
docker compose up -d
```

That pulls two prebuilt images and starts them in seconds. The app runs on [localhost:1401](http://localhost:1401), all that is left is to create an account and start using the vault - there is nothing to configure if you are just running it locally.

A fresh instance starts in **personal mode** - a private, single-user vault, ready as-is. To run it for a team, switch to [organization mode](organization.md) from Settings → Account; no restart or config edit needed.

The database lives in a Docker volume (`librelock_sqlite_data`) and survives restarts and updates. It is deleted only by `docker compose down -v`.

Anything you do want to change goes in a `.env` file next to `compose.yaml` - port, version, bind address, all of it optional. Take the annotated template and edit it:

```bash
curl -o .env https://raw.githubusercontent.com/LibreLock/.github/main/.env.example
```

Every setting in it is already at its default, so change only what you care about - a deleted line falls back to the same value:

```ini
LIBRELOCK_PORT=<PORT>
```

Then `docker compose up -d`. Editing `.env` later takes required running `docker compose up -d` again to apply.

## HTTPS is required

LibreLock encrypts everything in the browser using the [Web Crypto API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Crypto_API), which browsers expose **only in a secure context**: `https://` or `localhost`. Serving the app over plain HTTP on an IP or a LAN hostname (`http://192.168.1.10:1401`, `http://nas.local:1401`) leaves `crypto.subtle` undefined and the app cannot unlock, encrypt, or even sign you in.

So: `localhost` for a local install, HTTPS for everything else. There is no third option.

## Beyond localhost

If you want to self-host LibreLock on your domain, you need a certificate (app required HTTPS). The easiest way is to use Caddy since it handles certificates from Let's Encrypt automatically. Two situations, and they need different certificate challenges:

- **The host is reachable from the internet.** Point an `A` (and `AAAA`) record at it, keep ports 80 and 443 open, and Caddy solves the HTTP challenge on its own. Start with [Caddy in the same stack](#caddy-in-the-same-stack-recommended).
- **The host only exists on your local network** (`domain.com` resolving to `192.168.x.x`). Let's Encrypt cannot reach it, so the HTTP challenge fails and you need a DNS challenge - see [Internal domains](#internal-domains-and-wildcard-certificates).

### Caddy, in the same stack (recommended)
Caddy gets and renews certificates from Let's Encrypt by itself. Grab the two extra files and set the domain:

```bash
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/compose.caddy.yaml
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/Caddyfile
```

Then set three values in `.env` - the last two are at the bottom of the template, commented out (grab the template with the `curl -o .env` line from [Quick start](#quick-start) if you do not have one yet):

```ini
LIBRELOCK_DOMAIN=vault.example.com
LIBRELOCK_BIND=127.0.0.1
COMPOSE_FILE=compose.yaml:compose.caddy.yaml
```

and start it with `docker compose up -d`.

`LIBRELOCK_BIND=127.0.0.1` keeps the plain-HTTP app port off the public interface; Caddy reaches the web container over the internal Docker network.

That is the whole configuration - the [`Caddyfile`](../Caddyfile) is one block:

```caddyfile
{$LIBRELOCK_DOMAIN} {
	encode zstd gzip
	header Strict-Transport-Security "max-age=31536000; includeSubDomains"
	reverse_proxy {$LIBRELOCK_UPSTREAM}
}
```

`COMPOSE_FILE` is what keeps this to plain `docker compose` from here on - `up`, `logs -f`, `pull` all pick up both files by themselves. Without it every command needs `-f compose.yaml -f compose.caddy.yaml`.

### Caddy already running on the host

Skip `compose.caddy.yaml` entirely. Set `LIBRELOCK_BIND=127.0.0.1` in `.env` so the app port is only reachable from the host itself, run the plain stack, and add one block to your existing Caddyfile:

```caddyfile
vault.example.com {
	reverse_proxy 127.0.0.1:1401
}
```

Nothing else is needed - no path rewriting, no separate `/api` route, no upload-size or timeout tuning. If you already serve several apps behind one wildcard site, LibreLock is one more `handle`:

```caddyfile
*.asgard.lan.si {
	import cf

	@librelock host librelock.asgard.lan.si
	handle @librelock {
		reverse_proxy 127.0.0.1:1401
	}
}
```

Then `LIBRELOCK_PORT` in `.env` is how you keep it from colliding with the other stacks on that host.

### Internal domains and wildcard certificates

A hostname that only resolves inside your network still needs a real certificate - browsers give no secure context, and therefore no Web Crypto, to a self-signed one you have not installed as trusted, and none at all to plain HTTP. The way out is the **DNS-01 challenge**: Caddy proves it controls the domain by writing a TXT record, so the host never has to be reachable from the internet.

You need a domain you control at a supported DNS provider, and a Caddy binary with that provider's plugin. `caddy:2-alpine` ships without DNS plugins, so build one:

```dockerfile
# Caddyfile.dockerfile
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

Point the overlay at it instead of the stock image, and pass the API token through:

```yaml
# compose.caddy.yaml
services:
  caddy:
    build:
      dockerfile: Caddyfile.dockerfile
    environment:
      CF_API_TOKEN: ${CF_API_TOKEN:?}
```

and add the `tls` block to the site:

```caddyfile
{$LIBRELOCK_DOMAIN} {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
	encode zstd gzip
	reverse_proxy {$LIBRELOCK_UPSTREAM}
}
```

Swap `cloudflare` for your provider's [caddy-dns module](https://github.com/caddy-dns) - the plugin name, the import path, and the credential env var all change together.

Already running Caddy on the host with a wildcard certificate for `*.internal.example.com`? Then none of this applies to LibreLock: reuse the site you have and add the `handle` block above. Nothing about LibreLock's own certificate handling changes - it never sees TLS at all.

Two more notes for internal-only instances:

- **HSTS**: the shipped `Caddyfile` sets `Strict-Transport-Security` with `includeSubDomains`. That is right for a public instance and awkward for an internal one - browsers that saw it refuse plain HTTP for that host and everything under it for a year, which bites if something below it is HTTP-only. Delete the `header` line if that is your situation. Setting HSTS on a *wildcard* site, where it covers every service on the domain, is a decision worth making deliberately.
- **`APP_ENV=production`** is still correct. The cookie is `Secure`, and the connection is HTTPS; being internal changes nothing.

### Another reverse proxy

Any proxy works; it needs to terminate TLS and forward everything to the web container as one origin. Do not try to split `/api` off - the web container already handles that. Two things to get right:

- forward `X-Forwarded-For`, and keep `TRUSTED_PROXIES` covering the proxy's address, or every user shares one rate-limit bucket
- do not strip or rewrite the path

Cloudflare Tunnel, Tailscale Serve, and similar work too, as long as the browser ends up on `https://`.

## Configuration

All settings are environment variables read from `.env` next to `compose.yaml`. Defaults are in [`.env.example`](../.env.example).

| Variable | Default | What it does |
| --- | --- | --- |
| `LIBRELOCK_VERSION` | `latest` | Image tag both containers run: `latest`, a major (`1`), or an exact release (`1.2.3`) |
| `LIBRELOCK_PORT` | `1401` | Host port the app is served on |
| `LIBRELOCK_BIND` | `0.0.0.0` | Address that port is published on; `127.0.0.1` when a reverse proxy fronts it |
| `TOKEN_TTL` | `3600` | Session lifetime in seconds |
| `TRUSTED_PROXIES` | private ranges | Proxies whose `X-Forwarded-For` is believed, for rate limiting and session IPs |
| `APP_ENV` | `production` | `production` marks the session cookie `Secure`; only lower it if you must serve over plain HTTP |
| `UPGRADE_BACKUPS` | `true` | Snapshot the database into `backups/` before a new version migrates it; `false` only where the disk cannot hold a second copy |
| `LIBRELOCK_DOMAIN` | - | Domain Caddy serves, `compose.caddy.yaml` only |

Everything else - personal vs organization mode, whether sign-ups are open or invite-only, logo, name, support links - is set in the app itself and stored in the database. See [Organization Mode](organization.md) and [Customization](customization.md).

## Updating

```bash
docker compose pull
docker compose up -d
```

The database is untouched; the server applies schema changes on startup.

When the version changes, the server snapshots the database before migrating it, into `backups/` inside the same volume - `librelock-<old version>-<timestamp>.db`, the three newest kept. If an upgrade goes wrong, stop the stack, put that file back as `librelock.db`, and pin `LIBRELOCK_VERSION` to the old release. Those snapshots sit on the same disk as the original, so they are an undo button, not a [backup](#backups) - keep taking those too.

`LIBRELOCK_VERSION` in `.env` decides what `pull` gets. The default `latest` moves with every release; `LIBRELOCK_VERSION=1` takes fixes within a major version, `1.2.3` freezes until you change it.

LibreLock has **one version number**. The app and the API are separate containers but are built from the same tag and published under the same image tag, so `LIBRELOCK_VERSION` sets both and Settings → About shows a single version. It splits into two lines only if they somehow disagree - a stale cached bundle, or images pinned separately by hand.

## Building from source

Images are built by CI from the public repositories, so there is nothing you have to build. If you would rather build anyway - a patch of your own, or you do not want to trust the registry - swap the two `image:` lines in `compose.yaml` for the `build:` lines commented right under them, then:

```bash
docker compose build --pull
docker compose up -d
```

Expect a few minutes and about 1 GB of RAM for the frontend build. Pin the source by changing the branch in those URLs to a tag: `...librelock-server.git#v1.2.0`.

## Backups

The volume `librelock_sqlite_data` holds the entire instance. Vault contents stay encrypted - the server has never had the keys - but the file also holds every user's password hash, so **keep snapshots off the server and encrypted at rest**.

SQLite runs in WAL mode, so copying `librelock.db` alone is not enough - recent writes sit in `librelock.db-wal` until they are checkpointed. Take a consistent snapshot into the current folder while the stack keeps running:

```bash
docker run --rm -v librelock_sqlite_data:/data -v .:/out alpine sh -c "apk add -q --no-cache sqlite && sqlite3 /data/librelock.db '.backup /out/librelock-backup.db'"
```

`.backup` is SQLite's online-backup API: it reads through an open connection, so it picks up whatever is still in the WAL and writes one self-contained file. Everything inside the quotes runs in the container, which is why this one line is identical on Linux, macOS, PowerShell and `cmd`.

For a scheduled job you want the date in the name. Only the line that reads the date differs - the `docker` line is the same on both:

```bash
# Linux/macOS, for cron
d=$(date +%F)
docker run --rm -v librelock_sqlite_data:/data -v .:/out alpine sh -c "apk add -q --no-cache sqlite && sqlite3 /data/librelock.db '.backup /out/librelock-$d.db'"
```

```powershell
# Windows PowerShell, for Task Scheduler
$d = Get-Date -Format yyyy-MM-dd
docker run --rm -v librelock_sqlite_data:/data -v .:/out alpine sh -c "apk add -q --no-cache sqlite && sqlite3 /data/librelock.db '.backup /out/librelock-$d.db'"
```

Verify a snapshot before trusting it - this prints `ok`, and needs no `sqlite3` installed on the host:

```bash
docker run --rm -v .:/out alpine sh -c "apk add -q --no-cache sqlite && sqlite3 /out/librelock-backup.db 'PRAGMA integrity_check'"
```

Restore instructions are in the [server README](https://github.com/LibreLock/librelock-server#backups).

This is separate from the automatic pre-upgrade snapshots described under [Updating](#updating), which live in the same volume as the database and only protect you from a bad upgrade.

This is separate from the per-user [Export](export-import.md), which decrypts one vault in the browser. That one protects a user moving their data; this one protects the operator whose disk died.

## Running without Docker

That is a development setup, not a deployment - `go run .` and `npm run dev`, covered by CONTRIBUTING in [librelock-server](https://github.com/LibreLock/librelock-server/blob/main/CONTRIBUTING.md) and [librelock-web](https://github.com/LibreLock/librelock-web/blob/main/CONTRIBUTING.md). With both cloned side by side, [`run-local.sh`](../run-local.sh) / [`run-local.ps1`](../run-local.ps1) start the pair and stop both on Ctrl-C.

## Splitting the API onto its own origin

Not recommended - it buys nothing and adds CORS - but if you must serve the API from, say, `https://api.example.com`:

1. build the web image with `--build-arg VITE_API_BASE_URL=https://api.example.com`
2. set `ALLOWED_ORIGIN=https://vault.example.com` on the API
3. widen `connect-src` in `nginx.conf.template` to include the API origin, or the browser's CSP will block the calls

## Troubleshooting

**Blank page or "unable to unlock", nothing in the API logs.** The page is not in a secure context - you are on plain HTTP with a hostname other than `localhost`. See [HTTPS is required](#https-is-required).

**`/api` calls 502.** The API container is unhealthy or still starting: `docker compose logs api`.

**Everyone gets rate-limited (429) at once.** `TRUSTED_PROXIES` does not cover your reverse proxy, so every request looks like it comes from the same address.

**Caddy will not get a certificate.** For the default HTTP challenge, DNS must resolve to this host and ports 80/443 must be reachable from the internet: `docker compose logs caddy`. If the hostname is internal-only, the HTTP challenge cannot work at all - switch to [DNS-01](#internal-domains-and-wildcard-certificates).

**Signed in, immediately signed out again.** The session cookie is marked `Secure`, and the browser is dropping it because the page is plain HTTP on something other than `localhost`. Use HTTPS; as a last resort set `APP_ENV=development` in `.env`, which sends the cookie without the flag.

**Port already in use.** Set `LIBRELOCK_PORT` in `.env`.
