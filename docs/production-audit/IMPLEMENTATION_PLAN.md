# Implementation plan (proposed — nothing implemented yet; awaiting approval)

Ordered, smallest-safe-first. Effort: S ≤ ½ day, M ≈ 1–2 days, L ≈ 3–5 days (one engineer). Every task ends with: regression test added → relevant suites rerun → result recorded in TEST_RESULTS.md.

## Phase 0 — unblock verification (can start immediately, no code risk)
| # | Task | Effort | Depends | Acceptance |
|---|---|---|---|---|
| 0.1 | Run `firebase deploy --only firestore:rules --dry-run` on dev & prod; record result (SEC-1) | S | cloud access | outcome documented; if refused, go to 1.1 |
| 0.2 | Create a **staging** Firebase project + environment entry; document deploy order | M | owner | `main_uat.dart` points to a real project; rules/indexes/functions deployed there |
| 0.3 | Enable PITR + scheduled backups (dev/staging first); do one restore into a scratch DB (OPS-1) | M | 0.2 | restore record filled in; counts & `InvoiceReconciler` checked |
| 0.4 | Keystore, `key.properties`, Apple signing, APNs key, VAPID key, Meta secrets | M | owner | signed AAB verified (`apksigner`), TestFlight build installs, secrets present (names checked, values not printed) |

## Phase 1 — release blockers (code)
| # | Task | Effort | Depends | Acceptance / tests |
|---|---|---|---|---|
| 1.1 | **SEC-1** shrink `firestore.rules` (factor predicates, remove dead helpers) + CI size gate (< 200 KB) + dry-run deploy step | M–L | 0.1 | dry-run OK on dev & prod; 437+ rules tests still pass; gate fails a +60 KB file |
| 1.2 | **ACAD-1** UTC-midnight year writes + `startDateKey/endDateKey` + rules validation + one-off migration script (dry-run default) + read from keys only; fix the school-year registry the same way | L | — | tests under `TZ=Asia/Kolkata`, `America/Los_Angeles` (CI matrix); leave on year-end day accepted; migration idempotent on a copy |
| 1.3 | **NOTIF-1/STATE-3** central blocking-with-timeout unregister before every sign-out; device `lastSeenAt` expiry; delete devices on status/`login.enabled` change & session revoke | M | — | widget test per sign-out path; node test stale-device skip |
| 1.4 | **NOTIF-3/4/5** `retry`, re-runnable FAILED claims or sweeper, paging beyond 2,000, atomic takeover, timeouts | M | — | node tests: resolver throws once then sends; 2,500 recipients all attempted |
| 1.5 | **CFG-1** fail release builds without signing key; CI Android build job | S | 0.4 | build without key fails |
| 1.6 | **OPS-2/3** Crashlytics Gradle + iOS symbols; **LOG-1** remove PII from logs + unit test; alert policies | M | 0.4 | test crash visible; `errorSink` test passes; alerts exist |
| 1.7 | **SEC-2** register App Check, enforce on staging then prod (phone OTP only after) | S–M | 0.2, 0.4 | unattested callable rejected on staging |

## Phase 2 — integrity & user-visible defects
| # | Task | Effort | Acceptance |
|---|---|---|---|
| 2.1 | ACAD-2 `admissionNumbers/{lower}` reservations (admit, import, update, branch transfer) + rule | M | rules: two creates → one allow; case variant denied |
| 2.2 | ACAD-7 transactional in-branch transfer; ACAD-4 `approvedSheets` via transaction/increment; ACAD-3 reload-and-rebase | M | parallel tests described in RACE_CONDITION_AUDIT.md |
| 2.3 | STATE-1/2 move Students/Parents lists to `PagedListController`; request tokens elsewhere | M | out-of-order/double-tap/error widget tests |
| 2.4 | UI-1, UI-2 surface failures instead of success; ROUTE-2 `?from=` restoration | M | widget/router tests |
| 2.5 | ACAD-9 attendance rule: require student's current section & tie `dateKey` to `attendanceDate`; add an attendance write-plan contract fixture | M | rules tests for forged section/date; contract replay |
| 2.6 | NOTIF-2 login-enabled gate on push; ACAD-6 defer scheduled notices | S–M | node tests |
| 2.7 | CFG-6 add staff composite indexes (verify on dev project); DEP-1 upgrade `firebase-admin`/`firebase-functions`; SEC-4 per-tenant paging for `feeDueReminders`; PERF-1/2 | M–L | `npm audit --omit=dev` clean of highs; functions tests pass; reminders reach every tenant |

## Phase 3 — hardening
CSP + cache headers (CFG-4), CI permissions/pinning/prod-entry web build/Android build/dependabot (CFG-7/8), `.gitignore` additions (CFG-9), SEC-3 OTP TTL/IP source, SVG upload restriction (SEC-6), route-map completeness test (ROUTE-1), kDebugMode-gate `debugPrint` (LOG-2), clear Firestore persistence on sign-out (STATE-7), STATE-4/6, remaining P3s.

## Phase 4 — release rehearsal
Run DEPLOYMENT_CHECKLIST.md end-to-end on staging with at least two schools × two branches, real devices (Android, iOS) and the web app; record evidence; then repeat on production with a canary school.

## Dependencies at a glance
0.2 → (0.3, 1.7, 4); 0.4 → (1.5, 1.6, 1.7); 0.1 → 1.1; 1.2 before any school adopts school-wide years; 2.1 before bulk imports at scale.
