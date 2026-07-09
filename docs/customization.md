# Customization (White-Labeling)

Organization instances can replace the default LibreLock branding with their own — company name, logo, support links, and a login message.
Branding shows on the sidebar and the login and registration screens.

If nothing is set, LibreLock falls back to its built-in name and padlock logo automatically.

> **Availability:** Customization is an **organization-mode, admin-only** feature.
> In personal mode there is no customization UI and the app always shows the default LibreLock brand.
> See [organization.md](organization.md) for modes and roles.

## What you can customize

| Field | Where it shows | Notes |
| --- | --- | --- |
| **Company name** | Sidebar, login/register screens | Blank falls back to “LibreLock”. |
| **Company logo** | Everywhere the padlock icon appears | PNG, JPEG, SVG, WebP or GIF. Max **512 KiB**. |
| **Support email** | “Contact support” link on the auth screens | Optional. |
| **Support URL** | “Help center” link on the auth screens | Optional. |
| **Login message** | Shown under the logo on the login screen | Up to 500 characters. |

## How to customize (UI)

1. Sign in as an **admin** on an organization instance.
2. Open **Organization → Customization** (the Organization link is in the sidebar, above Settings — admins only).
3. Under **Company logo**, click **Upload logo** and pick an image (≤ 512 KiB).
   Use **Reset to default** to go back to the LibreLock padlock.
4. Under **Branding**, set your company name, support email/URL, and an optional login message, then click **Save changes**.

Changes apply immediately for every user of the instance.

## API reference

Branding lives under `/organization`.
The two `GET` routes are **public** (so the login screen can brand itself before sign-in); the write routes require an authenticated **admin** (organization mode).

| Method | Route | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/organization` | public | Branding + `mode`/`registration` as JSON. |
| `GET` | `/organization/logo` | public | Raw logo image bytes (404 if none set). |
| `PUT` | `/organization` | admin | Update name / support / login message. |
| `PUT` | `/organization/logo` | admin | Upload a logo (base64 data URL). |
| `DELETE` | `/organization/logo` | admin | Remove the logo, reverting to default. |

### `GET /organization`

```json
{
  "organization": {
    "name": "Acme Corp",
    "support_email": "support@acme.example",
    "support_url": "https://help.acme.example",
    "login_message": "Welcome to the Acme password vault.",
    "has_logo": true,
    "logo_updated_at": "2026-07-07T18:57:02Z",
    "mode": "organization",
    "registration": "open"
  }
}
```

`has_logo` tells the client whether to render `/organization/logo` or fall back to the built-in padlock.
`logo_updated_at` doubles as a cache-buster.
`mode` and `registration` let the frontend adapt before sign-in.

### `PUT /organization`

All fields optional; only the fields you send are updated.
Send an empty `name` to revert to “LibreLock”.

```bash
curl -X PUT https://your-instance/organization \
  -H 'Content-Type: application/json' \
  --cookie 'token=<admin-session-token>' \
  -d '{
    "name": "Acme Corp",
    "support_email": "support@acme.example",
    "support_url": "https://help.acme.example",
    "login_message": "Welcome to the Acme password vault."
  }'
```

### `PUT /organization/logo`

The logo is sent as a base64 **data URL**.
Allowed types: `image/png`, `image/jpeg`, `image/svg+xml`, `image/webp`, `image/gif`.
Max decoded size 512 KiB.

```bash
curl -X PUT https://your-instance/organization/logo \
  -H 'Content-Type: application/json' \
  --cookie 'token=<admin-session-token>' \
  -d '{"data": "data:image/png;base64,iVBORw0KGgoAAAANS..."}'
```

### `DELETE /organization/logo`

Removes the stored logo; the app reverts to the LibreLock padlock.

## Data model

Branding is a single-row `organization` table (fixed primary key `org`), created automatically on first read:

| Column | Type | Description |
| --- | --- | --- |
| `id` | text (PK) | Always `org` (singleton). |
| `name` | text | Company name; defaults to `LibreLock`. |
| `logo_data` | blob | Raw logo bytes (empty = use default). |
| `logo_mime_type` | text | MIME type of the stored logo. |
| `support_email` | text | Support contact email. |
| `support_url` | text | Support/help URL. |
| `login_message` | text | Message shown on the login screen. |
| `registration` | text | Sign-up policy `open` or `invite` (default `invite`); admin-toggled, see [organization.md](organization.md). |
| `created_at` / `updated_at` | timestamp | Managed automatically. |

The logo is stored in the database (not on disk), so it is included in your normal SQLite backups — no extra files to copy.

## Notes & security

- Branding is **not** encrypted: it is public by design (the login screen must render it before authentication).
  Do not put anything sensitive in these fields.
- Uploads are validated by MIME type and size limit (512 KiB) on the server.
- Write access is restricted to admins via the `RequireAdmin` middleware; in personal mode the write routes are disabled entirely.

## Roadmap ideas

Fields that pair well with this feature if you want to extend it:

- **Favicon** upload (separate from the main logo).
- **Terms / Privacy URLs** shown on the login and registration screens.
- **Org-enforced password policy** (min length, complexity) applied at register and password-change time.
- **Session timeout policy** configurable per instance.
