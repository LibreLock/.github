# Organization Mode (Teams, Roles & Invites)

LibreLock runs in one of two **modes**, chosen per instance:

- **Personal** (default) — a private, single-user (or shared-household) vault.
  No roles, no admin area, plain LibreLock branding.
- **Organization** — a company instance with **roles** (admin / member), an **Organization** admin area, white-label **customization**, and optional **invite-only** registration.

The same binary and database serve both.

## Configuration

There is **no config file**. A fresh instance starts in **personal** mode and runs as-is.
The mode is stored in the database (the `app_state` row) and can be switched to **organization** from inside the app — no restart, no file to edit.

The server logs the resolved mode on startup:

```
mode=personal
```

To turn a personal instance into an organization one, sign in and open **Settings → Account → Switch to organization** (the card sits just above *Delete account*).
You confirm a warning, and the account you are signed in with becomes the **owner**.
See [Switching modes](#switching-modes).

> **Reverting is destructive and owner-only.**
> Only the **owner** can go back to personal mode, from **Organization → Management → Return to personal mode**.
> It **permanently deletes every other user and all of their data**, keeping only the owner.
> Guarded by password re-authentication and a typed confirmation phrase.

> **Registration policy is not a config setting either.**
> Whether sign-up is invite-only or open is an **admin setting toggled in-app** (Organization → Management → Registration), stored on the organization row.
> It defaults to the safer **invite-only**. See [Registration](#registration) below.

## Roles

Roles apply **only in organization mode** (in personal mode the column exists but is ignored).

| Role | Can do |
| --- | --- |
| **owner** | Everything an admin can, **plus** revert the whole instance to personal mode and **transfer ownership** to another user. The founder of the organization. Exactly one. |
| **admin** | Everything a member can, plus: the Organization area — customization, user management, and invites. |
| **member** | Normal vault use. No access to the Organization area. |

- The **first account** (the founder) becomes the **owner** — either the user who switches a personal instance to organization mode, or the first to register on a fresh organization instance.
- If an organization database somehow has no owner (e.g. it predates the role), the **oldest** user is promoted to owner on the next startup (`bootstrap: promoted "<user>" to owner` in the logs).
- The **owner is protected**: it cannot be demoted, suspended, or removed through user management, and only the owner can revert to personal mode.
- There is always **at least one active admin** (owner counts): the last one cannot be demoted, suspended, or removed.

## The Organization page

Admins get an **Organization** link in the sidebar (above Settings). It has:

- **Users** — list everyone with a role **dropdown** (member / admin, plus **owner** for the current owner — choosing it **transfers ownership** after a confirmation, demoting the old owner to admin).
  A per-row **⋮ menu** holds **suspend / reactivate** and **remove** (which deletes their vault too).
  You cannot change your own account here; use Settings for that.
- **Invites** — only shown when `registration` is `invite` (see below).
- **Customization** — company branding. See [customization.md](customization.md).
- **Management** — the registration policy (see [Registration](#registration)) and, for the **owner** only, **Return to personal mode** (see [Switching modes](#switching-modes)).
- **Audit log** — a chronological record of administrative activity (see below).

Members do not see this link, and the routes reject non-admins server-side.

### Suspend vs remove

Two ways to cut off a user, with different consequences:

- **Suspend** (reversible) — the account can no longer log in and its live sessions are terminated immediately, but **the vault is kept**.
  Reactivate to restore access. Use this for offboarding, leaves, or suspected compromise.
- **Remove** (permanent) — deletes the account and **cascade-deletes the vault**, categories, and sessions.
  Under end-to-end encryption a removed vault cannot be recovered, so prefer **suspend first**.

The **last active admin** cannot be demoted, suspended, or removed, so an instance always keeps at least one usable admin.

### Audit log

Every administrative action is recorded (organization mode only) and shown newest first under **Organization → Audit log**.
Actor and target **names are snapshotted**, so entries stay readable even after the referenced user is removed.

Recorded actions: organization enabled (the very first entry), account created, role changed, ownership transferred, user suspended / reactivated / removed, invite created / revoked, and branding / logo changes.

## Registration

The policy is set by an admin under **Organization → Management → Registration** (no restart, no config edit).
It defaults to **invite-only**.
Switching to public is treated as a dangerous action and requires confirming a warning dialog.

### Open (public sign-up)

Anyone who can reach the instance can create an account from the register page; new accounts are **members** (except the very first, which is the owner).

### Invite-only (default)

Public sign-up is disabled. To add a member:

1. An admin opens **Organization → Invites → New invite** (an optional note, e.g. the person's email, helps you track it).
2. LibreLock generates a **single-use link**: `https://your-instance/register?invite=<token>`.
   **Copy it now — the token is shown only once.**
3. The invitee opens the link and completes registration, choosing **their own master password** (end-to-end encryption means nobody else — not even an admin — ever knows it).

Invites are single-use.
The expiry is **configurable per invite** (1–90 days, default **1**) via the "Expires (days)" field.
Used or expired invites show their status in the list and can be revoked.

> **Why not "admin creates the account"?**
> The master password derives the vault's encryption key in the browser and never reaches the server.
> An admin therefore cannot set someone's password for them — the invite flow lets each user set their own while still gating who may join.

The **first** account on a fresh invite-mode instance is still allowed to register **without** a token (and becomes the owner) — otherwise there would be no one to create invites.

## API reference

Admin routes live under `/organization` and require an authenticated **admin** session (organization mode).
See customization endpoints in [customization.md](customization.md).

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/organization/users` | List all accounts (id, username, role, status, created_at). |
| `PUT` | `/organization/users/:id/role` | Body `{"role":"owner"\|"admin"\|"member"}`. Blocks demoting the last admin; the **owner** cannot be targeted. `role:"owner"` is an **ownership transfer** (owner-only): the target becomes owner and the caller is demoted to admin, atomically. |
| `PUT` | `/organization/users/:id/status` | Body `{"status":"active"\|"suspended"}`. Suspending kills the user's sessions; blocks suspending the last admin. |
| `PUT` | `/organization/registration` | Body `{"registration":"open"\|"invite"}`. Toggles the sign-up policy (audited). |
| `DELETE` | `/organization/users/:id` | Remove a user and cascade-delete their data. Blocks removing the last admin. |
| `POST` | `/organization/invites` | Body `{"note":"…","expires_in_days":1}` (`expires_in_days` optional, 1–90, default 1). Returns the raw `token` **once**. |
| `GET` | `/organization/invites` | List invites with `status` (pending/used/expired). |
| `DELETE` | `/organization/invites/:id` | Revoke an invite. |
| `GET` | `/organization/audit` | Recent audit entries newest first (`?limit=` 1–500, default 100). |

Switching a personal instance to organization mode uses a settings route, not an `/organization` one (there is no admin yet to gate it):

| Method | Route | Purpose |
| --- | --- | --- |
| `PUT` | `/settings/mode` | Body `{"mode":"organization"}` (auth required) — the caller becomes the **owner**. Or `{"mode":"personal","auth_credential":"…"}` (**owner only**, destructive) — deletes every other user and their data, drops the org tables, reverts the mode. No-op if already in the requested mode. |

Registration accepts an optional `invite_token` field; it is required for non-first accounts when `registration` is `invite`.

`GET /organization` (public) includes `mode` and `registration` so the frontend and login/register pages know how to behave before sign-in.

## Data model

- `app_state` — singleton row (PK `app`) holding the deployment `mode` (`personal` default, or `organization`).
  Always present; read live on each request. Replaces the old `config.json`.
- `user.role` — `text`, `owner`, `admin`, or `member` (default `member`, ignored in personal mode).
  Exactly one `owner` (the founder) exists in organization mode.
- `user.status` — `text`, `active` or `suspended` (default `active`; suspended users cannot log in, enforced in organization mode).
- `invite` — one row per invite: `id`, `token_hash` (SHA-256; the raw token is never stored), `note`, `created_by`, `expires_at`, `used_at`, `created_at`.
- `audit_event` — one row per admin action: `id`, `action`, `actor_id`, `actor_name`, `target_id`, `target_name`, `detail`, `created_at`.
  Names are snapshotted so entries survive user deletion.

## Switching modes

- **Personal → Organization**: in the app, **Settings → Account → Switch to organization**, confirm the warning.
  The switching user becomes the owner, the organization-only tables (`organization`, `invite`, `audit_event`) are created, and the mode is persisted.
  No restart. Existing vault data is untouched.
- **Organization → Personal**: **Organization → Management → Return to personal mode** (**owner only**).
  This is **destructive**: it permanently deletes every account except the owner — cascade-deleting their vaults, categories, and sessions — then drops the organization tables (`organization`, `invite`, `audit_event`) and reverts the mode.
  The surviving owner is demoted to a plain personal user and stays logged in.
  Guarded by password re-authentication plus a typed confirmation phrase (`delete <organization name>`).
  A full wipe is still possible by deleting `data/librelock.db`.

Both switches happen live (the `RequireAdmin` guard and registration logic read the mode on every request), so the Organization area appears/disappears without a restart.
