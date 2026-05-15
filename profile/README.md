<div align="center">
  <img src="../images/logo.svg" alt="LibreLock logo" height="70" />
  <h1 align="center">LibreLock</h1>
</div>

LibreLock is a secure, modern, self-hosted password manager. Manage your passwords, credit cards, and notes securely all in one place.

## Features
- **Secure vault**: Store your credentials, credit card details, and notes.
- **Client-side encryption**: All vault data is encrypted in the browser using AES-256-GCM before being sent to the server. Server stores only encrypted blobs and password hashes, non of which it can read. For more, see Cryptography Overview bellow.
- **Password health monitoring**: Each password is checked against the [Have I Been Pwned](https://haveibeenpwned.com) breach database using k-anonymity. Passwords are also scored for strength and flagged if reused across multiple entries.
- **Categorization**: Organize your vault items into categories or assign them colors for easy identification.
- **Session management**: View all active sessions with device name, IP address, and last-used timestamp. Revoke individual sessions or all sessions at once from the settings page.
- **Light/dark theme**: toggle between light and dark mode; theme persistes in local storage.
- **Open source**: LibreLock is fully open source. You can self-host it on your own server or contribute to the project on GitHub.


## Get Started

The recommended way to run LibreLock is with Docker Compose. The backend API and frontend web app are in separate repositories, both use Docker Compose for easy setup.
<br>
If you prefer to run without Docker, follow instructions in `README.md` files found in both backend and frontend repositories.

### Backend
1. Clone the repository and navigate into it:
    ```bash
    git clone https://github.com/librelock/librelock-api.git
    cd librelock-api
    ```
1. Copy `.env.example` to `.env` and update database credentials if needed.
    ```bash
    cp .env.example .env
    ```
2. Run the setup script to generate `APP_KEY`:
    ```bash
    chmod +x setup.sh
    ./setup.sh
    ```
3. Start the application:
    ```bash
    docker compose up -d --build
    ```

The API is now running at [localhost:8000](http://localhost:8000). MySQL data persists in a Docker volume across restarts.

### Frontend

```bash
git clone https://github.com/librelock/librelock-web.git
cd librelock-web
docker compose up -d
```

Open [localhost:1401](http://localhost:1401). Create an account and start managing your secrets.


## Cryptography Overview

Librelock uses client-side encryption with key wrapping. The server never sees plaintext vault data or the master password - all vault data is encrypted with AEK before being sent to the server.

### Key Hierarchy

```
MasterPassword
     │
     ▼ Argon2id (kdf_salt, kdf_iter, kdf_memory, kdf_parallelism)
     │
MasterKey (256-bit, never leaves client)
     ├─── HKDF("auth")  ──► auth_credential  ──► server stores Argon2id(auth_credential)
     └─── HKDF("wrap")  ──► WrappingKey
                                 │
                                 ▼ AES-256-GCM encrypt
                            AccountEncryptionKey (AEK)  ──► server stores as protected_key
                                 │
                                 ▼ AES-256-GCM encrypt
                            vault item ciphertexts  ──► server stores encrypted_blob + iv
```

### Key Roles

| Key | Where it lives | Purpose |
|-----|----------------|---------|
| `MasterPassword` | User's head | Input to KDF |
| `MasterKey` | Client RAM only | KDF output, never stored or sent |
| `auth_credential` | Sent to server once (login/register) | Authentication only, bcrypt hash stored |
| `WrappingKey` | Client RAM only | Derived from MasterKey, wraps AEK |
| `AEK` (Account Encryption Key) | Client RAM; encrypted form in DB | Single key that encrypts all vault items |
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
7. Server stores `bcrypt(auth_credential)`, `protected_key`, KDF params

### Login

1. Client fetches KDF params: `GET /api/auth/kdf?username=alice`
2. Client derives `MasterKey`, then `auth_credential` and `WrappingKey`
3. Client sends `auth_credential` to server
4. Server returns user object including `protected_key`
5. Client decrypts: `AEK = AES-256-GCM-Decrypt(protected_key, WrappingKey)`
6. Client uses AEK to decrypt vault items

### Changing Master Password

Because vault items are encrypted with AEK (not directly with MasterKey), changing the master password only requires re-wrapping the AEK - vault items remain untouched.

1. Client derives old `MasterKey` and verifies with `current_auth_credential`
2. Client derives new `MasterKey` from new master password + new KDF params
3. Client re-derives `new_WrappingKey = HKDF(newMasterKey, "wrap")`
4. Client re-wraps: `new_protected_key = AES-256-GCM(AEK, new_WrappingKey)` - AEK is unchanged
5. Client derives `new_auth_credential = HKDF(newMasterKey, "auth")`
6. Client sends new credentials and protected key to server, vault items remain encrypted under the same AEK

Server atomically updates `auth_hash`, KDF params, and `protected_key`, then invalidates all other active sessions.
