<div align="center">
  <img src="../images/logo.svg" alt="LibreLock logo" height="70" />
  <h1 align="center">LibreLock</h1>
</div>


LibreLock is a self-hosted modern password manager, built out of distrust in third-party password managers.

## Features
- **Store passwords and notes**: Save your credentials and sensitive information securely.
- **Client-side encryption**: All vault data is encrypted on the client before sending to the server - server never sees vault items or master passwords. Vault is encrypted with a single Account Encryption Key (AEK) that is wrapped by the master key, allowing for secure and efficient encryption.
- **Password health monitoring**: Each password is checked against the [Have I Been Pwned](https://haveibeenpwned.com) breach database using k-anonymity. Passwords are also scored for strength and flagged if reused across multiple entries.
- **Categorization**: Organize your vault items into custom categories for easy management.
- **Session management**: View and revoke active sessions across devices for enhanced security.
- **Open source**: LibreLock is fully open source. You can self-host it on your own server or contribute to the project on GitHub.


## Get Started
1. Clone frontend and backend repositories:
    ```bash
    git clone https://github.com/librelock/librelock-web.git
    git clone https://github.com/librelock/librelock-server.git
    ```
2. Setup MySQL database:
    ```bash
    cd librelock-server
    docker run -d -p 3306:3306 --name librelock-db -e MYSQL_ROOT_PASSWORD=YOUR_PASSWORD mysql:latest
    ```
3. Build and run the backend:
    ```bash
    cd librelock-server
    docker build -t librelock-server .
    docker run -d -p 8000:8000 --name librelock-server librelock-server
    ```
4. Build and run the frontend:
    ```bash
    cd librelock-web
    docker build -t librelock-web .
    docker run -d -p 1401:1401 --name librelock-web librelock-web
    ```
5. Open [localhost:1401](http://localhost:1401) to access LibreLock. Create a new account from the [register page](http://localhost:1401/register) and start managing your passwords securely!


## Cryptography Overview

Librelock uses client-side encryption with key wrapping. The server never sees plaintext vault data or the master password - all vault data is encrypted with AEK before being sent to the server.

### Key Hierarchy

```
MasterPassword
     │
     ▼ Argon2id (kdf_salt, kdf_iter, kdf_memory, kdf_parallelism)
     │
MasterKey (256-bit, never leaves client)
     ├─── HKDF("auth")  ──► auth_credential  ──► server stores bcrypt(auth_credential)
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
