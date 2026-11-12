# RBAC matrix

| Capability | Platform admin | School admin | Branch admin | Teacher | Finance | Parent |
|---|---|---|---|---|---|---|
| See Admissions in the app (`manageAdmissions`) | ✅ (project convention: platform admin holds every permission; with no school/branch the page shows "No branch found") | ✅ | ✅ | – | – | – |
| Read enquiries and history (rules) | ✅ support | ✅ | ✅ own branch | – | – | – |
| Create / edit / assign / change status (callables) | – | ✅ any branch | ✅ own branch | – | – | – |
| Read settings (rules) | ✅ | ✅ | ✅ | – | – | – |
| Open / save settings (UI `manageSchool`, callable) | – | ✅ | – | – | – | – |
| Schedule / reschedule / reassign / complete / cancel follow-ups (callables) | – | ✅ any branch | ✅ own branch | – | – | – |
| Receive follow-up reminders | – | ✅ when assigned or no branch admin exists | ✅ when assigned or unassigned in their branch | – | – | – |
| Start / edit / submit applications, upload / verify / remove documents, take into review, comment | – | ✅ | ✅ own branch | – | – | – |
| Approve or reject an application | – (no school) | ✅ | ✅ **only if the school enables it**, own branch | – | – | – |
| View documents (Storage rules) | ✅ support | ✅ | ✅ own branch | – | – | – |
| Admission-staff role | not built | | | | | |

Enforced in three places that must agree: `RolePermissions` (what the UI offers),
`firestore.rules` (reads), `functions/admission.js` (writes). Tests: `route_permissions_test`,
`admission_ui_test` ("who can open it"), `admission-rules.test.mjs`, `admission.test.js`.
