# RBAC matrix

| Capability | Platform admin | School admin | Branch admin | Teacher | Finance | Parent |
|---|---|---|---|---|---|---|
| See Admissions in the app (`manageAdmissions`) | ✅ (project convention: platform admin holds every permission; with no school/branch the page shows "No branch found") | ✅ | ✅ | – | – | – |
| Read enquiries and history (rules) | ✅ support | ✅ | ✅ own branch | – | – | – |
| Create / edit / assign / change status (callables) | – | ✅ any branch | ✅ own branch | – | – | – |
| Read settings (rules) | ✅ | ✅ | ✅ | – | – | – |
| Open / save settings (UI `manageSchool`, callable) | – | ✅ | – | – | – | – |
| Admission-staff role | not built | | | | | |

Enforced in three places that must agree: `RolePermissions` (what the UI offers),
`firestore.rules` (reads), `functions/admission.js` (writes). Tests: `route_permissions_test`,
`admission_ui_test` ("who can open it"), `admission-rules.test.mjs`, `admission.test.js`.
