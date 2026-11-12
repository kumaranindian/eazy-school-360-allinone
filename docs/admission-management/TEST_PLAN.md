# Test plan and current coverage

| Layer | File | What it proves | Count |
|---|---|---|---|
| Server logic (applications and documents) | `functions/admission_applications.test.js` | numbering, lifecycle and its effect on the enquiry, approval prerequisites (required documents, school-defined types), decision authority, enquiry closing, upload request/confirm/verify/remove, size/type mismatch, idempotency, caps, abandoned-upload cleanup, file-signature check, tenant/role isolation | 33 |
| Server logic (follow-ups and visits) | `functions/admission_activities.test.js` | visit booking and the status effects (book, several visits, complete, cancel last / with earlier completed visit, reschedule, hold detaches, close cancels), generic call refuses visits, scheduling, idempotent retry, concurrency, reschedule/reassign/complete/cancel, atomic next contact, append-only history, derived enquiry fields, closing cancels follow-ups, tenant/role isolation, reminders (due/overdue, once only, rescheduled, time zone and window, recipients, no personal data, failure isolation) | 47 |
| Server logic | `functions/admission.test.js` | state machine, validation, numbering (+ concurrency), duplicates, role/tenant/branch isolation, client-supplied identity ignored, history order, stale revisions | 23 |
| Deletion coverage | `functions/deletion_coverage.test.js` | new collections have a deletion decision | in suite |
| Rules (emulator) | `firestore-tests/admission-rules.test.mjs` | who can read; nobody writes (enquiries, history, activities, activity history, applications, application history, documents); sequences server-only; cross-school/branch denied | 10 |
| Storage rules | `firestore-tests/admission-storage-rules.test.mjs` | read scope, create-only against a server-approved upload (status, enquiry, path, size, content type), size/type caps, no delete — **written but not executed successfully here: the Storage emulator in the build sandbox also fails the existing Storage-rules suites, so even the allow-cases fail; run it in CI before relying on it** | 6 |
| Domain | `test/admission/admission_domain_test.dart` | statuses, option table parity, search classification, query plan, models, payload, activities, visits, merged timeline, notification routing, applications, documents, upload limits, custom type ids | 42 |
| UI | `test/widget/admission_ui_test.dart` | dashboard, role access, list search/filter, form validation and payload, details actions, history, settings, follow-up dashboard buckets, activity dialogs and server-failure handling, reminder settings, school visits (booking, tabs, completion notes, cancel/reschedule, closed enquiry, merged timeline, dashboard list and tiles), applications (start, edit, submit, review, decide, branch-admin authority, list), documents (progress, upload flow with retry and local limits, verify/reject/remove, frozen after decision, viewer), application settings, layout at 5 sizes | 127 |
| Existing | `route_permissions_test`, `role_permissions_test`, shell tests | permission map and navigation still consistent | in suite |

## Not yet tested (honest list)
- Real Firestore: the repository's queries (`FirebaseAdmissionRepository`) are untested against an
  emulator; only the pure query plan and fakes are. The index set was written by reasoning, not by a
  failed-query run — deploy to **dev** first and exercise each filter.
- The callables are tested as plain functions with an in-memory Firestore, not through the
  Functions emulator / HTTP layer (App Check, auth token plumbing).
- Real transaction contention beyond the in-memory fake (retry limits).
- Reminder delivery end to end: the scheduled function and the push path are tested up to the `notifications` document (the existing `pushNotification` trigger sends it, which has its own tests); nothing here was run against a deployed function.
- The follow-up dashboard queries (`status`/`scheduledDate`/`assignedTo`/`completedAt` orderings and the `isNull` + `whereIn` count) are not run against an emulator.
- The Storage rules and the real upload/confirm round trip (Storage emulator or dev project). The Dart upload path is tested against a fake store; `FirebaseAdmissionDocumentStore` is not.
- PDF rendering in the viewer (`PdfPreview`) is not exercised by a test (images are).
- Everything in phases 7–16.
