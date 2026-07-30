# Export & Import

LibreLock can write a vault out to a portable JSON file and read one back in. Useful for moving to another instance, keeping a personal off-site copy, or seeding a new account.

Entries are decrypted with the vault key you already hold in browser memory, and an import is written back through the ordinary create-entry routes. The server never sees plaintext in either direction, which also means it cannot help you if a backup file's password is lost.

> **Availability:** Every user can export and import their own vault from Settings → Export & Import.
> On organization instances, admins get the same for the shared vault under Organization → Export & Import, provided they have shared-vault access.
> See [organization.md](organization.md) for modes and roles.

## Exporting

1. Open Settings → Export & Import (or Organization → Export & Import for the shared vault).
2. Leave **Protect the file with a password** on and enter a backup password twice.
3. Click **Export vault**. The file downloads as `librelock-personal-YYYY-MM-DD.json` (or `librelock-shared-…`).

The backup password is independent of your account password and is never stored or sent anywhere. Lose it and the file is unreadable, there is no recovery path.

Turning the toggle off produces a plaintext export instead, named `…-plaintext.json`, containing every password, card number, and note in the clear. It is there for migrating into another password manager; treat the file as the vault itself and delete it once you are done.

## Importing

1. Open the same tab and choose a `.json` backup file.
2. If it is password-protected, enter its backup password and click *Unlock file*. A summary appears: export date, whether it was encrypted, and how many entries and categories it holds.
3. Leave *Skip duplicates* on to ignore entries the vault already has (matched on type + name + the primary secret — password, card number, or note body).
4. Click *Import N entries…* and confirm. A progress bar runs while entries are created one by one.

Import only ever adds: existing entries are never overwritten or deleted, so a bad import is undone by deleting what it created. When it finishes you get a count of imported, skipped, and failed entries.

Categories are matched by name, not id, so files move cleanly between accounts and instances. Any category in the file that the vault lacks is created first; entries whose category could not be created (shared categories are admin-only) are still imported, just uncategorised, and named in the result.

Importing a file exported from a different scope works, the tab warns you when a shared export is being imported into a personal vault or vice versa, but does not block it. Anything imported into the shared vault is visible to every member with shared-vault access.

## File format

| Field | Meaning |
| --- | --- |
| `format` | Always `librelock.backup`, files without it are rejected. |
| `version` | Format version (currently `1`). A newer file is rejected rather than half-read. |
| `scope` | `personal` or `shared`, the vault it came from. |
| `exportedAt` | ISO timestamp, shown in the import summary. |
| `encrypted` | Whether the payload is protected. |
| `payload` | Plaintext exports only: `{ categories, entries }`. |
| `kdf` + `data` | Encrypted exports only: Argon2id parameters (salt, iterations, memory, parallelism) and `base64(iv ‖ ciphertext)` of the payload. |

Encrypted files use the same primitives as the vault itself: Argon2id derives a key from the backup password (64 MB memory, 4 iterations, 4 lanes, fresh random salt) and AES-256-GCM encrypts the serialised payload. See [cryptography.md](cryptography.md) for how the vault keys work.

Each entry carries its name, colour, icon, category name, timestamps, and its type-specific fields (`password` / `note` / `card`). Timestamps are informational only, the server stamps its own on import. Unknown entry types, entries without a name, and colours outside the palette are dropped or defaulted while parsing, so a hand-edited file cannot inject unexpected values.

## Notes & security

- **A plaintext export is an unencrypted copy of your vault.** Prefer the password-protected form, and store either off the machine that made it.
- Backup passwords are not recoverable. Neither the server nor the browser keeps a copy.
- Export decrypts in the browser, so it works only while the vault is unlocked. For the shared vault you must have been granted access; without it the tab explains how to get it instead of showing the form.
- This is not an operator backup. It covers one vault's entries — not users, sessions, invites, organization settings, or the audit log. For whole-instance snapshots, see the Backups section of the librelock-server README.
