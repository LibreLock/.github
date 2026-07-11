# Customization (White-Labeling)

Organization instances can replace the default LibreLock branding with their own — company name, logo, support links, and a login message.
Branding shows on the sidebar and the login and registration screens.

If nothing is set, LibreLock falls back to its built-in name and padlock logo automatically.

> **Availability:** Customization is an organization-mode, admin-only feature.
> In personal mode there is no customization UI and the app always shows the default LibreLock brand.
> See [organization.md](organization.md) for modes and roles.

## What you can customize

| Field | Where it shows | Notes |
| --- | --- | --- |
| **Company name** | Sidebar, login/register screens | Blank falls back to “LibreLock”. |
| **Company logo** | Everywhere the padlock icon appears | PNG, JPEG, SVG, WebP or GIF. Max 512 KiB. |
| **Support email** | “Contact support” link on the auth screens | Optional. |
| **Support URL** | “Help center” link on the auth screens | Optional. |
| **Login message** | Shown under the logo on the login screen | Up to 500 characters. |

## How to customize (UI)

1. Sign in as an admin on an organization instance.
2. Open Organization → Customization (the Organization link is in the sidebar, above Settings — admins only).
3. Under Company logo, click Upload logo and pick an image (≤ 512 KiB).
   Use Reset to default to go back to the LibreLock padlock.
4. Under Branding, set your company name, support email/URL, and an optional login message, then click Save changes.

Changes apply immediately for every user of the instance.

## Notes & security

- Branding is not encrypted: it is public by design (the login screen must render it before authentication).
  Do not put anything sensitive in these fields.
- Uploads are validated by MIME type and size limit (512 KiB) on the server.

## Roadmap ideas

Fields that pair well with this feature if you want to extend it:

- **Favicon** upload (separate from the main logo).
- **Terms / Privacy URLs** shown on the login and registration screens.
- **Org-enforced password policy** (min length, complexity) applied at register and password-change time.
- **Session timeout policy** configurable per instance.
