<div align="center">
  <img src="../content/logo.svg" alt="LibreLock logo" height="60" />
  <h1 align="center">Cryptography & Session Handling</h1>
</div>

How LibreLock protects your data: client-side encryption, key wrapping, the authentication flow, the organization shared vault, and how unlocked sessions are kept in the browser.

## Cryptography Overview

Librelock uses client-side encryption with key wrapping. The server never sees plaintext vault data or the master password - all vault data is encrypted with AEK before being sent to the server.

Users create an account with a username (up to 500 characters) and a master password (12 to 10000 characters). The password is run through Argon2id (4 iterations, 64 MB memory, parallelism 4, with a random 32-byte salt) to derive a 256-bit **master key**, which never leaves the client. Two subkeys are derived from it via HKDF-SHA-256: an **auth credential** that proves identity to the server (stored only as an Argon2id hash) and a **wrapping key** that encrypts/decrypts the vault key (never stored anywhere).

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

## Organization Shared Vault

Organization mode adds a shared vault that members can read and write in common. It keeps the same zero-knowledge guarantee — the server never sees the shared key or any private key — using the standard model of a per-user keypair plus one symmetric key enveloped to each member.

### Per-user keypair

Every account gets an RSA-OAEP keypair (3072-bit modulus, SHA-256), generated in the browser at registration:

- The **public key** is uploaded and stored in plaintext on the server (`user.public_key`); it is not secret.
- The **private key** is exported (PKCS8) and encrypted with AES-256-GCM under the same password-derived wrapping key that protects the vault key, then stored as `user.encrypted_private_key` (IV prepended). The server only ever holds the wrapped form.

Accounts created before this feature are backfilled on their next login: while the wrapping key is available, the client generates a keypair and uploads it once (idempotent server-side, so a second attempt is a no-op).

### The shared organization key

Shared entries are all encrypted under a single random **organization key** (AES-256-GCM). This key is never stored on the server in any form the server can read. Instead, one copy per member is stored, each RSA-OAEP-enveloped to that member's public key in `org_vault_membership.wrapped_key`.

- *Bootstrap.* The first admin/owner to enable sharing generates the organization key in the browser, envelopes it to their own public key, and self-grants (writes their own membership row). The key stays in memory for the session.
- *Granting a member.* An admin who currently holds the organization key envelopes it to the target member's public key and posts the result as a new membership. This needs only the target's public key, never their password or private key, so an admin can grant (or re-grant, as recovery) access without the member present.
- *Loading the key.* On login a member fetches their own enveloped copy (`GET /org/shared-key`) and decrypts it with their RSA private key to recover the organization key into memory.

### Shared entries

Shared entries live in a separate `org_vault` table with no owning-user column — they outlive whoever created them, and access is gated by membership rather than row ownership. Each row is an AES-256-GCM ciphertext (`encrypted_blob` + `iv`) under the organization key, exactly like personal entries but keyed on the shared key. Server-side, every shared-vault route requires an active membership; a request from a user without one is rejected with `403`.

### Password changes and revocation

- *Changing the master password* re-wraps the private key the same way it re-wraps the vault key: the client decrypts the private key with the old wrapping key and re-encrypts it under the new one. The public key and all memberships stay valid — the organization key is never re-enveloped, because it is bound to public keys, which do not change.
- *Revoking access* deletes the member's membership row, so their next shared-vault request gets `403`. This does not rotate the organization key: a revoked member already saw it while a member, so anything they previously read or exported stays readable to them. True forward secrecy requires key rotation (generating a new organization key, re-enveloping it to the remaining members, and re-encrypting every shared entry), which is a documented future extension, not yet built.

### Key Roles (organization sharing)

| Key | Where it lives | Purpose |
|-----|----------------|---------|
| `public_key` | Server DB, plaintext | Envelope the org key to a member; not secret |
| `private_key` (RSA) | Client RAM; wrapped form in DB | Unwraps the member's copy of the org key |
| `encrypted_private_key` | Server DB | AES-GCM ciphertext of the private key under the WrappingKey |
| `OrgKey` (AES-256) | Client RAM; per-member enveloped copies in DB | Single key that encrypts all shared entries |
| `wrapped_key` | Server DB (one row per member) | `OrgKey` RSA-enveloped to that member's public key |

## Session Handling

Once unlocked, the client holds its keys in memory as `CryptoKey`s and mirrors them to IndexedDB: the non-extractable **vault key** (`AEK`), plus — for org members with shared access — the user's **RSA private key** and the **organization shared key**. A `vault_unlocked` flag in `sessionStorage` gates all of them. Since `sessionStorage` survives a reload but is per-tab and cleared on close, reloading the same tab restores the keys from IndexedDB with no re-derivation, while a freshly opened tab (no flag) cannot read them.

To unlock a new tab without re-entering the master password, it requests the keys from other tabs over a `BroadcastChannel`; any already-unlocked tab replies. If none answers within a short timeout, the tab stays locked and the user must authenticate.

---

Back to the [main README](../profile/README.md) or the [documentation index](README.md).
