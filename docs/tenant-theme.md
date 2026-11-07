# Tenant-wide theme

A school's branding is **one configuration per tenant**, not a user preference.
When a School Admin saves it, every user of that school — School Admin, Branch
Admin, Teacher, Finance, Parent, on every branch and device — gets the same
colours, live. Another school is never affected.

## Data model

| Document | Who reads | Who writes |
|---|---|---|
| `schools/{s}/branding/config` | every member of school `s`; platform admins | only the `updateSchoolBranding` callable |
| `platformBranding/default` | any signed-in user | only the `updatePlatformBranding` callable |

```
schools/{s}/branding/config = {
  schoolId, version, preset, colors | null, appearance, updatedAt, updatedBy
}
platformBranding/default = { version, defaultPreset, presets: { id: { label, colors } }, updatedAt, updatedBy }
```

* `colors` has seven `#RRGGBB` values: `primary`, `secondary`, `accent`,
  `surface`, `background`, `text`, `selectedNav`. `null` means "use the platform
  default" (never customised, or reset).
* `appearance` is `system` (default, follows the device), `light` or `dark`.
* `version` only grows. A **reset keeps the document** (colours `null`, version
  +1), so a client can always discard a snapshot older than the one applied.
  `updateSchoolBranding` also accepts `baseVersion`; a stale one fails with
  `aborted` instead of overwriting someone else's save.
* The school **logo** stays where it was: `schools/{s}.logoUrl`.
* Status colours (success, warning, error, info) are **not** tenant-controlled,
  so a school cannot turn an overdue marker green.

## Authorization and tenant isolation

* `updateSchoolBranding`: the SCHOOL_ADMIN **of that school**, or a
  PLATFORM_ADMIN (any school). Branch Admin, Teacher, Finance, Parent and other
  schools' admins get `permission-denied`. The caller must be ACTIVE and allowed
  to sign in (`loginAllowed`).
* `updatePlatformBranding`: PLATFORM_ADMIN only (default preset, custom presets;
  built-in preset ids cannot be replaced).
* Rules deny every client write to both documents; reads are scoped to the
  caller's own school. `firestore-tests/branding-rules.test.mjs` covers each
  role, another school, signed-out users and writes.
* Client: the listener is built from the signed-in user's own tenant. A branding
  document whose `schoolId` is not the expected one is rejected, the on-device
  cache is keyed by school, and between two accounts (signed-in user ≠ loaded
  tenant) the platform default is shown, so one school's colours cannot show for
  another school's user.
* The login screen has no tenant yet, so it always shows the **platform
  default** (not a cached school).

## Readability

`functions/branding.js` (server) and `BrandColors.problems()` (client, same
rules) check every colour set: text on surface and on background ≥ 4.5:1;
secondary, selected navigation on surface ≥ 3:1; accent on surface ≥ 2:1 (a
highlight colour that never carries text alone; the approved default gold is
2.3:1). Button text colour is computed (white or near-black). The server
refuses an unreadable set; the client, if it ever finds one stored, replaces
the offending colours with the default's (`BrandingResolver`).

## Client architecture

* `lib/core/branding/tenant_branding.dart` — pure domain: `BrandColors`,
  presets, `TenantBranding`, `PlatformBranding`, `BrandingResolver`.
* `lib/core/theme/app_theme.dart` — `AppTheme.light/dark([ResolvedTheme])`.
  The default colour set reproduces the approved design exactly; any other set
  is derived from the seven colours (dark mode lifts brand colours until they
  read on dark surfaces). `BrandTheme` (a `ThemeExtension`) carries what
  `ColorScheme` has no slot for: selected navigation, a deep primary, the hero
  gradient.
* `lib/features/branding/presentation/providers/branding_providers.dart` —
  `tenantThemeProvider`: live listeners on the school and platform documents,
  stale-version guard, per-school cache (`shared_preferences`), error ⇒ keep
  what is showing. `lib/app/app.dart` feeds it into `MaterialApp`.
* Screens never hardcode tenant colours: use `Theme.of(context).colorScheme`,
  `BrandTheme.of(context)` or `context.brandTone(color)` for legacy palette
  constants.

## Screens

* Settings → Branding (School Admin and Platform Admin): presets, custom
  colours with a live readability check, appearance, logo (via School profile),
  live preview, save, reset to platform default.
* Settings → Platform branding (Platform Admin): default preset and custom
  presets for all schools.

## Deletion

`branding` is a school collection scanned by the deletion processor (its
`updatedBy` is anonymised); `platformBranding` is exempt (no personal data).
