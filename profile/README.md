<div align="center">
  <img src="../content/logo.svg" alt="LibreLock logo" height="70" />
  <h1 align="center">LibreLock</h1>
</div>

LibreLock is a secure, modern, self-hosted password manager. Manage your passwords, credit cards, and notes securely all in one place. Built for individuals and teams who value privacy and control over their data.

<div align="center">
  <img src="../content/demo.gif" alt="LibreLock Demo" width="1000" />
</div>

## Features
- **Secure vault**: Securely store passwords, credit card details, and notes.
- **Client-side encryption**: All vault data is encrypted in the browser using AES-256-GCM before being sent to the server. The server stores only encrypted blobs and password hashes, none of which it can read. For more, see [Cryptography & Session Handling](../docs/cryptography.md).
- **Personal and organization mode**: Use LibreLock as a personal password manager or create an organization with multiple users, roles, and invite-only registration.
- **Password health monitoring**: Each password is checked against the [Have I Been Pwned](https://haveibeenpwned.com) breach database using k-anonymity. Passwords are also scored for strength and flagged if reused across multiple entries.
- **Categorization**: Organize your vault items into categories, assign them icons and colors for easy identification.
- **Export & import**: Export and import entire vault contents to a JSON file, protected with a password of your own.
- **Session management**: View all active sessions with device name, IP address, and last-used timestamp. Revoke individual sessions or all sessions at once from the settings page.
- **Light/dark theme**: toggle between light and dark mode; theme persistes in local storage.

## Get Started

Running LibreLock is as simple as:
```bash
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/compose.yaml
docker compose up -d
```


Then simply open [localhost:1401](http://localhost:1401) and create an account and start using the vault. Updating later is `docker compose pull`, then `docker compose up -d`.

A fresh instance starts in **personal mode** - private, single-user vault, ready as-is. To run LibreLock for a team, sign in and switch to **organization mode** from Settings → Account → Switch to organization (no restart or config edit needed); the account you switch with becomes the owner. See [Organization Mode](../docs/organization.md).

There is only one port and one origin: the web container serves the app and proxies `/api` to the API container, and the whole instance is a single embedded SQLite database in a Docker volumes, so it survives restarts and updates. There is nothing to configure to get started. If you want to go further later, settings go in a `.env` file next to `compose.yaml` - see [Configuration](../docs/self-hosting.md#configuration) for more.

To stop LibreLock, run:
```bash
docker compose down     # stop
docker compose down -v  # stop and delete the database volume (dangerous)
```

### Hosting it on a domain

Serving LibreLock anywhere other than `localhost` **requires HTTPS** - the browser exposes the Web Crypto API, which does all the encryption only in a secure context. A ready-made [Caddyfile](../Caddyfile) and Compose overlay handle the certificate for you:

```bash
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/compose.caddy.yaml
curl -O https://raw.githubusercontent.com/LibreLock/.github/main/Caddyfile
curl -o .env https://raw.githubusercontent.com/LibreLock/.github/main/.env.example
```

The last line grabs the annotated settings template - skip it if you already have a `.env`. Set three values in it, in any text editor (the last two are at the bottom, commented out):

```ini
LIBRELOCK_DOMAIN=vault.example.com
LIBRELOCK_BIND=127.0.0.1
COMPOSE_FILE=compose.yaml:compose.caddy.yaml
```

then:

```bash
docker compose up -d
```

Point DNS at the host and Caddy gets and renews the certificate from Let's Encrypt on its own. Full guide, including other reverse proxies, backups, updating, and every setting: [Self-Hosting](../docs/self-hosting.md).

Working on LibreLock source? Development setup lives in [librelock-server](https://github.com/LibreLock/librelock-server) and [librelock-web](https://github.com/LibreLock/librelock-web).

## Documentation

Guides live in [`docs/`](../docs/README.md):

- [Self-Hosting](../docs/self-hosting.md) — run your own instance: one-command setup, ports, HTTPS and reverse proxies, configuration, updating, and backups.
- [Organization Mode](../docs/organization.md) — teams, roles (admin/member), user management, and invite-only registration.
- [Customization](../docs/customization.md) — white-label your instance with your own logo, company name, and support details.
- [Export & Import](../docs/export-import.md) — back up or move a vault: encrypted and plaintext backup files, how imports merge, and the file format.
- [Cryptography & Session Handling](../docs/cryptography.md) — client-side encryption, key wrapping, the authentication flow, and browser session handling.

## Tech Stack
- **Backend**: REST API built with [Go](https://go.dev/) and [Gin](https://gin-gonic.com/). Uses [SQLite](https://sqlite.org/)
- **Frontend**: Single-page application web application built with [Vue](https://vuejs.org/) and [Vite](https://vitejs.dev/).

## Security

LibreLock is end-to-end encrypted: vault data is encrypted in the browser with AES-256-GCM before it reaches the server, which only ever stores encrypted blobs and password hashes it cannot read. For the full design — key wrapping, the authentication flow, and how unlocked sessions are handled in the browser — see [Cryptography & Session Handling](../docs/cryptography.md).
