<div align="center">
  <img src="../content/logo.svg" alt="LibreLock logo" height="70" />
  <h1 align="center">LibreLock</h1>
</div>

LibreLock is a secure, modern, self-hosted password manager. Manage your passwords, credit cards, and notes securely all in one place. Built for individuals and teams who value privacy and control over their data.

<div align="center">
  <img src="../content/demo.gif" alt="LibreLock Demo" width="1000" />
</div>

## Features
- **Secure vault**: Store your credentials, credit card details, and notes.
- **Client-side encryption**: All vault data is encrypted in the browser using AES-256-GCM before being sent to the server. Server stores only encrypted blobs and password hashes, non of which it can read. For more, see Cryptography Overview bellow.
- **Password health monitoring**: Each password is checked against the [Have I Been Pwned](https://haveibeenpwned.com) breach database using k-anonymity. Passwords are also scored for strength and flagged if reused across multiple entries.
- **Categorization**: Organize your vault items into categories or assign them colors for easy identification.
- **Session management**: View all active sessions with device name, IP address, and last-used timestamp. Revoke individual sessions or all sessions at once from the settings page.
- **Light/dark theme**: toggle between light and dark mode; theme persistes in local storage.
- **Responsive design**: the UI adapts to different screen sizes, from mobile to desktop.
- **Open source**: LibreLock is fully open source. You can self-host it on your own server or contribute to the project on GitHub.


## Get Started

The recommended way to run LibreLock is with Docker Compose. Clone [librelock-server](https://github.com/librelock/librelock-server) and [librelock-web](https://github.com/librelock/librelock-web), then run the provided `run` script from this repo to build and start both with one command:

```bash
git clone https://github.com/librelock/librelock-server.git
git clone https://github.com/librelock/librelock-web.git

# Linux/macOS
# Get the script from https://github.com/LibreLock/.github/blob/main/run.sh
chmod +x ./run.sh
./run.sh

# Windows (PowerShell)
# Get the script from https://github.com/LibreLock/.github/blob/main/run.ps1
./run.ps1
```

This copies `.env.example` to `.env` for the backend, then runs `docker compose up -d --build` for both projects. The web app is served at [localhost:1401](http://localhost:1401) and the API at [localhost:8000](http://localhost:8000). The SQLite database lives in the `data/librelock.db` file inside `librelock-server` and persists across restarts.

To stop everything, run `./run.sh down` (or `./run.ps1 down`). To completely tear down the stack (including the database volume!) run `./run.sh down -v` (or `./run.ps1 down -v`).

To run without Docker (requires Go and Node.js), use `run-local.sh` / `run-local.ps1` instead. This starts the API with `go run` and the web app with `npm run dev`, and stops both on Ctrl-C.

To run the backend or frontend individually, see the `README.md` in [librelock-server](https://github.com/librelock/librelock-server) and [librelock-web](https://github.com/librelock/librelock-web).

## Documentation

Guides live in [`docs/`](../docs/README.md):

- [Organization Mode](../docs/organization.md) — teams, roles (admin/member), user management, and invite-only registration.
- [Customization](../docs/customization.md) — white-label your instance with your own logo, company name, and support details.

## Tech Stack
- **Backend**: REST API built with [Go](https://go.dev/) and [Gin](https://gin-gonic.com/). Uses [SQLite](https://sqlite.org/)
- **Frontend**: Single-page application web application built with [Vue](https://vuejs.org/) and [Vite](https://vitejs.dev/).

## Cryptography Overview
Librelock uses client-side encryption with key wrapping. The server never sees plaintext vault data or the master password - all vault data is encrypted with AEK before being sent to the server.

Users create an account with a username and a master password (at least 12 characters). The password is run through Argon2id (4 iterations, 64 MB memory, parallelism 4, with a random 32-byte salt) to derive a 256-bit **master key**, which never leaves the client. Two subkeys are derived from it via HKDF-SHA-256: an **auth credential** that proves identity to the server (stored only as an Argon2id hash) and a **wrapping key** that encrypts/decrypts the vault key (never stored anywhere).

A random 256-bit **vault key** (`AEK`) encrypts all vault items with AES-256-GCM. The vault key itself is encrypted ("wrapped") under the wrapping key using AES-256-GCM with a random 12-byte IV, producing the **protected key** - the only form of the vault key ever sent to or stored on the server.

### Key Roles

| Key | Where it lives | Purpose |
|-----|----------------|---------|
| `MasterPassword` | User's head | Input to KDF |
| `MasterKey` | Client RAM only | KDF output, never stored or sent |
| `auth_credential` | Sent to server once (login/register) | Authentication only, Argon2id hash stored |
| `WrappingKey` | Client RAM only | Derived from MasterKey, wraps AEK |
| `AEK` (vault key) | Client RAM; encrypted form in DB | Single key that encrypts all vault items |
| `protected_key` | Server DB | AES-GCM ciphertext of AEK under WrappingKey |

The AEK is generated once at registration and never changes. Only its encrypted wrapper `protected_key` is updated when the master password changes.

## Authentication Flow

### Register

1. Client runs Argon2id: `MasterKey = argon2id(masterPassword, kdf_salt, ...)`
2. Client derives `auth_credential = HKDF(MasterKey, "auth")`
3. Client derives `WrappingKey = HKDF(MasterKey, "wrap")`
4. Client generates a random 256-bit `AEK`
5. Client encrypts: `protected_key = AES-256-GCM(AEK, WrappingKey)` - IV prepended to ciphertext
6. Client sends to server: `username`, `auth_credential`, `protected_key`, KDF params
7. Server stores `argon2id(auth_credential)`, `protected_key`, KDF params

### Login

1. Client fetches KDF params: `GET /auth/kdf?username=alice`
2. Client derives `MasterKey`, then `auth_credential` and `WrappingKey`
3. Client sends `auth_credential` to server
4. Server returns user object including `protected_key` (see Key Roles table above)
5. Client decrypts: `AEK = AES-256-GCM-Decrypt(protected_key, WrappingKey)`
6. Client uses AEK to decrypt vault items

If the username does not exist, the server responds to step 1 with plausible, randomly generated KDF parameters instead of an error - this prevents an attacker from using `/auth/kdf` to enumerate registered usernames.

### Changing Master Password

Because vault items are encrypted with AEK (not directly with MasterKey), changing the master password only requires re-wrapping the AEK - vault items remain untouched.

1. Client derives old `MasterKey` and verifies with `current_auth_credential`
2. Client derives new `MasterKey` from new master password + new KDF params
3. Client re-derives `new_WrappingKey = HKDF(newMasterKey, "wrap")`
4. Client re-wraps: `new_protected_key = AES-256-GCM(AEK, new_WrappingKey)` - AEK is unchanged
5. Client derives `new_auth_credential = HKDF(newMasterKey, "auth")`
6. Client sends new credentials and protected key to server, vault items remain encrypted under the same AEK

Server atomically updates `auth_hash`, KDF params, and `protected_key`, then invalidates all other active sessions.

## Session Handling

Once the vault is unlocked, the vault key is kept in memory as a non-extractable `CryptoKey` and mirrored to IndexedDB, so reloading the page restores the session without re-entering the master password. A `vault_unlocked` flag in `sessionStorage` gates access to that IndexedDB entry - since session storage is per-tab and cleared when a tab closes, a new tab cannot silently pull the key from IndexedDB without authenticating first.
