# Organization Mode (Teams, Roles & Invites)

LibreLock runs in one of two modes chosen per instance:

- **Personal** (default) — a private, single-user (or shared-household) vault.
  No roles, no admin area, plain LibreLock branding. Sign-up closes once the first account exists; see [Personal instances](#personal-instances) for more.
- **Organization** — a company instance with roles (admin / member), an Organization admin area, white-label customization, and optional invite-only registration.

The same binary and database serve both.

## Personal instances

Personal instance is the default mode when running LibreLock. It's intended to be used by a single user with a single account. The first account created on the instance is the only one that can sign up (by default), and it becomes the owner. There are two ways to allow more accounts:

- **Sign-up** — closed as soon as the first account exists. Personal instance is intended to be used by a single user with a single account. If the goal is to have multiple users, switching to organizational mode is recommended. There is still however a way to create multiple accounts in personal mode (example use case is multiple accounts for a single user, e.g. work and personal). This is done in *Settings → Instance → Sign-up → Allow new accounts*.
- **Switch to organization** — see [Switching modes](#switching-modes).

Both are restricted to the **first account created on the instance**. Personal mode has no roles to gate on, and switching to organization mode makes the caller owner over every other account, so without this restriction any account could seize the instance. Other users see a read-only panel naming the first account, so they know who to ask.

## Configuration

There is no config file. A fresh instance starts in personal mode and runs as-is. The mode is stored in the database (the `app_state` row) and read live on every request.

To turn a personal instance into an organization one, sign in and open *Settings → Account → Switch to organization*. The account you are signed in becomes the owner of the organization.
See [Switching modes](#switching-modes).

> **Reverting is destructive and owner-only.**
> Only the owner can go back to personal mode, from Organization → Management → Return to personal mode.
> It permanently deletes every other user and all of their data, keeping only the owner.

> **Registration policy is not a config setting either.**
> Whether sign-up is invite-only or open is an admin setting toggled in-app (Organization → Management → Registration)
> It defaults to the safer invite-only. See [Registration](#registration) below.

## Roles

Roles apply only in organization mode (in personal mode the column exists but is ignored).

| Role | Can do |
| --- | --- |
| **owner** | Everything an admin can, plus revert the whole instance to personal mode and transfer ownership to another user. The founder of the organization. Exactly one. |
| **admin** | Everything a member can, plus: the Organization area — customization, user management, and invites. |
| **member** | Normal vault use. No access to the Organization area. |

- The first account (the founder) becomes the owner — either the user who switches a personal instance to organization mode, or the first to register on a fresh organization instance.
- If an organization database somehow has no owner (e.g. it predates the role), the oldest user is promoted to owner on the next startup.
- The owner is protected: it cannot be demoted, suspended, or removed through user management, and only the owner can revert to personal mode.
- There is always at least one active admin (owner counts): the last one cannot be demoted, suspended, or removed.

## The Organization page

Admins get an Organization link in the sidebar, from which they can manage:

- **Users** — list everyone with a role dropdown (member / admin, plus owner for the current owner — choosing it transfers ownership after a confirmation, demoting the old owner to admin).
  A per-row ⋮ menu holds suspend / reactivate and remove (which deletes their vault too).
  You cannot change your own account here; use Settings for that.
- **Invites** — only shown when `registration` is `invite` (see below).
- **Customization** — company branding. See [customization.md](customization.md).
- **Export & Import** — back up or restore the shared vault. Requires shared-vault access. See [export-import.md](export-import.md).
- **Management** — the registration policy (see [Registration](#registration)) and, for the owner only, Return to personal mode (see [Switching modes](#switching-modes)).
- **Audit log** — a chronological record of administrative activity (see below).

Members do not see this link, and the routes reject non-admins server-side.

### Suspend vs remove

Two ways to cut off a user, with different consequences:

- **Suspend** (reversible) — the account can no longer log in and its live sessions are terminated immediately, but the vault is kept.
  Reactivate to restore access. Use this for offboarding, leaves, or suspected compromise.
- **Remove** (permanent) — deletes the account and cascade-deletes the vault, categories, and sessions.
  Under end-to-end encryption a removed vault cannot be recovered, so prefer suspend first.

The last active admin cannot be demoted, suspended, or removed, so an instance always keeps at least one usable admin.

### Audit log

Every administrative action is recorded (organization mode only) and shown newest first under Organization → Audit log.
Actor and target names are snapshotted, so entries stay readable even after the referenced user is removed.

Recorded actions: organization enabled (the very first entry), account created, role changed, ownership transferred, user suspended / reactivated / removed, invite created / revoked, and branding / logo changes.

## Registration

The policy is set by an admin under *Organization → Management → Registration* (no restart, no config edit) and defaults to invite-only.
There are 2 modes to register:

### Invite-only (default)

To add a member:
1. An admin opens *Organization → Invites → New invite* (an optional note, e.g. the person's email, helps admins track it).
2. LibreLock generates a single-use link: `https://your-instance/register?invite=<token>`. Copy it now as the token is shown only once.
3. The invitee opens the link and completes registration, choosing their own master password (nobody else — not even an admin — ever knows it).

Invites are single-use, expiry is configurable per invite (1–90 days, default 1) via the "Expires (days)" field.
Used or expired invites show their status in the list and can be revoked.

### Open (public sign-up)

Anyone who can reach the instance can create an account from the register page; new accounts are members.
Switching to public sign-up is not recommended, as it allows anyone which can access the instance to create an account and become a member of the organization.
Especially dangerous when *Auto-grant shared vault* is enabled.

In both cases, it is recommended that organizations self hosting LibreLock lock access down to a private network or VPN, and keep registration invite-only.

## Switching modes

- **Personal → Organization**: in app, *Settings → Account → Switch to organization*, confirm the warning.
  The switching user becomes the owner, the organization-only tables (`organization`, `invite`, `audit_event`, `org_vault_membership`, `org_category`, `org_vault`) are created, and the mode is persisted.
  No restart is needed, existing vault data is untouched.
- **Organization → Personal**: in app, *Organization → Management → Return to personal mode* (owner only action).
  This is destructive: it permanently deletes every account except the owner — cascade-deleting their vaults, categories, and sessions, dropping the organization tables (`org_vault`, `org_category`, `org_vault_membership`, `audit_event`, `invite`, `organization`) and reverting the mode.
  A full wipe is still possible by removing the SQLite database — under Docker, `docker compose down -v` (drops the `librelock_sqlite_data` volume); running without Docker, stop the server and delete `librelock-server/data/librelock.db`.
