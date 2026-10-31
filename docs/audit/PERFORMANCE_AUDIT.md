# Performance and scalability audit

Audit date 2026-10-31 · read-only. **No load test exists in the repository and none was run.** Everything below about volume is either measured from code (counts, patterns) or an explicit estimate. It is not evidence that 10, 50, 100 or 1,000 schools, or 25,000+ students, perform acceptably.

## What was measured
| Item | Measured value | Source |
|---|---|---|
| Dart source | 537 files, ~110 k lines; 126 test files | `find lib`, `find test` |
| Firestore composite indexes | 92 indexes + 20 field overrides; guard test `tool/indexes.test.js` passes | `firestore.indexes.json` |
| Real-time listeners (`.snapshots()`) | 50 sites | `lib/**` |
| Server-side aggregates (`count()`) | 9 sites (stat chips, dashboards) | `lib/**` |
| Paged queries (`.limit(...)`) | 65 sites; invoices page by `dueDateKey` with `pageSize + 1` | `firebase_invoice_repository.dart:336,371` |
| Unbounded `get()`/`snapshots()` in `data/` | 33 sites by heuristic; every one I opened is naturally bounded (one section, one student, one parent's links, reference lists such as classes/sections/period sets) | `firebase_student_repository.dart`, `*_attendance_repository.dart`, `parent_access_sync.dart`, etc. |
| `autoDispose` providers | 130 uses (listeners are released when screens close) | `lib/**` |
| Bulk limits | 500 student rows per sheet; push recipient chunks handled in `recipients.js` | `bulk_student_import.dart:12` |
| Function config | `maxInstances: 10`, 256 MB, `asia-south1` (same as Firestore) | `functions/index.js`, `firebase functions:list` |
| Dependency state | 12 Dart packages locked behind newer compatible versions; 23 constrained below resolvable | `flutter pub outdated` |

## Findings
1. **Query shape is generally sound.** Lists are paged, counts are server aggregates, and the unbounded reads I checked are bounded by domain (a section's roster, a student's links). No collection-wide scan of a growing collection from the client was found. *Not verified:* that every query has its index in production (indexes are deployed from the file; an un-indexed query fails at run time, so each new screen needs a real run against the project).
2. **Security rules add billed reads.** Rules resolve the caller via `get(/users/{uid})` and, for teachers and parents, `teacherAccess`/`parentAccess` documents. Lookups are billed as reads and count against a per-request lookup limit; the team already restructured rules around the 1000-expression limit. Cost per query is small and constant; per-document writes (batches) multiply it. *Estimate only:* roughly one to three extra reads per query/operation.
3. **Counter hot spots.** Invoice and receipt numbers come from one counter document per branch updated transactionally (`feeCounters`), so numbering is limited to about one allocation per second per branch under contention; bulk invoice generation is sequential by design. Fine for pilot sizes; a single very large branch generating thousands of invoices will take minutes (OPS-4 was deferred).
4. **Sequential loops.** `ParentAccessSync.refreshParent` reads each child one at a time (bounded by siblings); bulk student import does about eight to ten round trips per row sequentially (500 rows is several minutes on a slow connection, and the page must stay open); admission numbers use one ordered query over a window of 50.
5. **Push fan-out.** Recipient lists were previously truncated at 2000 (NOTIF-4, fixed); fan-out is chunked, claims per delivery, with an hourly-class redrive. `feeDueReminders` runs every hour in UTC. Cost scales with schools × due invoices; no measurement exists.
6. **Client memory/rebuilds.** Widespread `autoDispose` and paging are positive; no profiling (frame times, leak checks) was run, so rebuild cost and image memory are unmeasured. Images picked from the camera are not downscaled in the app (`image_picker` is used without `maxWidth`/`imageQuality`); Storage rules cap sizes instead.
7. **Web payload.** The release web build succeeds in about 30-45 s (CanvasKit); first-load size was not measured.

## Scale scenarios
| Scenario | Evidence | Verdict |
|---|---|---|
| 1 school / pilot (hundreds of students) | Functional tests only | Expected fine; **not load-tested** |
| 10 schools | Per-tenant paths; no cross-tenant scans seen | Estimate: fine |
| 50-100 schools | Hourly reminders and redrive scale with data; function instance cap 10 | Estimate: needs a cost and concurrency rehearsal |
| 1,000 schools / 25,000+ students | Firestore itself scales horizontally; hot spots are per-branch counters, scheduled scans and rules lookups | **Unknown.** Treat as untested; run a synthetic load before committing |

## Recommendations
1. Create a synthetic dataset (e.g. 100 schools, 25 k students, 200 k invoices) in a scratch project and measure: student list/search latency, invoice generation for a 2,000-student branch, attendance for 60 sections at 8 a.m., result finalisation, and monthly Firestore cost.
2. Instrument Cloud Functions (duration, retries) and set budget alerts (OPS-3).
3. Measure web first-load size and add image downscaling before upload.
4. Keep the index guard test and add a smoke script that visits each screen against the dev project to catch missing indexes.
