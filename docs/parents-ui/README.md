# Parents module mobile UI revamp

Frontend only. No change to `functions/`, `firestore.rules`, `storage.rules`,
repositories, auth, permissions logic or providers.

Screenshots (test-font render, so some bold labels show as blocks): `mobile-*`,
`tablet-*`, `desktop-*` in this folder: 1-list, 2-details, 3-login-access.

## Feature-preservation checklist
Parents list: search (name-only), status filter, Filters sheet + chips, ⋮ menu
(Give login access, Reset passwords, Refresh parent access), selection mode +
bulk actions, per-row Login access key (canManage), pagination / Load more,
empty/error states, Add Parent, tap to open details.
Parent details: photo upload, name, status, phone, alternate phone, email,
occupation, address, edit dialog, portal-access text, children list with
navigation, empty-children state. NEW: Portal access card opens Login Access.
Login Access page (same `LoginAccessDialog` logic, `layout: page`): enable
switch + preserved text, permitted methods (school-disabled ones not
selectable), Send reset/setup email, Reset Password, Check Access, Sign Out All
Devices (confirmations kept), Save/Close, validation, loading, duplicate-submit
guard, result returned to caller. Staff dialog unchanged.

## Notes
- Route `/parents/:parentId/login-access` added (same permission as the key button).
- The dark page hero is the shared shell header; the duplicate light heading was dropped.
- Search placeholder stays "Search parents by name" because search is name-only.
- Baseline failures unrelated: `branding_shell_test`, `app_version_test`.
