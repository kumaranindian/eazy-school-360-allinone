# Test plan and current coverage

| Layer | File | What it proves | Count |
|---|---|---|---|
| Server logic | `functions/admission.test.js` | state machine, validation, numbering (+ concurrency), duplicates, role/tenant/branch isolation, client-supplied identity ignored, history order, stale revisions | 23 |
| Deletion coverage | `functions/deletion_coverage.test.js` | new collections have a deletion decision | in suite |
| Rules (emulator) | `firestore-tests/admission-rules.test.mjs` | who can read; nobody writes; sequences server-only; cross-school/branch denied | 6 |
| Domain | `test/admission/admission_domain_test.dart` | statuses, option table parity, search classification, query plan, models, payload | 17 |
| UI | `test/widget/admission_ui_test.dart` | dashboard, role access, list search/filter, form validation and payload, details actions, history, settings, layout at 5 sizes | 51 |
| Existing | `route_permissions_test`, `role_permissions_test`, shell tests | permission map and navigation still consistent | in suite |

## Not yet tested (honest list)
- Real Firestore: the repository's queries (`FirebaseAdmissionRepository`) are untested against an
  emulator; only the pure query plan and fakes are. The index set was written by reasoning, not by a
  failed-query run — deploy to **dev** first and exercise each filter.
- The callables are tested as plain functions with an in-memory Firestore, not through the
  Functions emulator / HTTP layer (App Check, auth token plumbing).
- Real transaction contention beyond the in-memory fake (retry limits).
- Everything in phases 4–16.
