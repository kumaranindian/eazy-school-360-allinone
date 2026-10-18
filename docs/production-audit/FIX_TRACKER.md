# Fix tracker — every finding, by priority

Single working list for remediation. Source: `BUG_REGISTER.md` (evidence, repro, fix detail) · ordering and dependencies: `IMPLEMENTATION_PLAN.md` · this file records **status**. Update the Status column in the same commit as the fix.

**Status legend:** ☐ TODO · ◐ in progress · ✔ fixed (code + regression test, suites green) · ⚑ owner action (needs cloud console / devices / keys — cannot be completed from the repo; a repo-side guard or runbook may still be ✔) · ⊘ accepted / design decision (needs owner sign-off) · ? re-verify first

## Working rules
1. **One finding at a time**: reproduce with a failing test (or document why a test cannot exist), fix minimally, run the affected suites, tick the row, commit. Never batch unrelated fixes in one commit.
2. **Race-condition standard (production requirement).** Any read-modify-write on shared data must be (a) a Firestore transaction that re-reads inside it, or (b) an atomic server operation (`FieldValue.increment/arrayUnion`, create-only reservation document, `create()` precondition), and always (c) idempotent under retry (deterministic document id or idempotency key). Client list/search loads carry a request-generation token. Every such fix ships with a test that runs the competing operations concurrently (fake with controllable futures for UI, Firestore emulator for rules/transactions) and asserts the single correct final state.
3. Rules changes need an allowed **and** a denied rules test; write-plan changes need the Dart contract fixture regenerated and replayed.
4. Run before every commit: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, the affected tests; full `flutter test`, `functions` tests and the rules suite at the end of each phase.

## P0 — critical
None confirmed.

## P1 — high
| ID | Title | Phase | Status |
|---|---|---|---|
| SEC-1 | Rules ruleset at the release-size edge; deployability unknown | 1 | ✔ repo side (built artifact 146 KB + CI gate); ⚑ run `tool/deploy_rules.sh <project> --dry-run` on dev/prod |
| NOTIF-1 | Previous user keeps pushes after non-button sign-out | 1 | ✔ |
| NOTIF-3 | Failed push deliveries never retried/redriven | 1 | ✔ |
| ACAD-1 | Academic-year dates off by one day in UTC+ zones | 1 | ✔ code/rules/tests/CI TZ matrix; ⚑ run `tool/migrate_year_dates.js --zone <zone>` (dry-run first) on existing data |
| CFG-1 | Release builds may be debug-signed | 1 | ✔ |
| OPS-2 | Crash reporting incomplete on Android/iOS | 1 | ⚑ |
| OPS-1 | No backup / PITR / restore drill | 0 | ⚑ |

## P2 — medium
| ID | Title | Phase | Status |
|---|---|---|---|
| STATE-1 | Students/Parents lists: double load-more, stale results, stuck spinner | 2 | ✔ |
| STATE-2 | Same race in leave-balance search, link-parent dialog, admission parent search | 2 | ✔ |
| UI-1 | Admission reports success when guardian create/link failed | 2 | ✔ |
| UI-2 | Results finalised with silently missing attendance | 2 | ✔ |
| ACAD-2 | Admission-number uniqueness is check-then-write | 2 | ✔ code+rules+tests; ⚑ run `tool/backfill_admission_numbers.js` (dry-run first) on existing data |
| ACAD-3 | Marks save partial failure; retry impossible | 2 | ✔ |
| ACAD-4 | `approvedSheets` read-modify-write outside transaction | 2 | ✔ |
| ACAD-7 | In-branch student transfer not transactional | 2 | ✔ (transaction + precondition; atomicity itself is Firestore's) |
| ACAD-9 | Attendance rules trust client section/date | 2 | ◐ date coherence enforced in rules; enrolment lookup per student is not possible (rules allow 20 document reads per commit, a register commit has 30+) - accepted residual risk: only the section's own teacher or a manager can write |
| NOTIF-2 | Disabled-login users still pushed / can register devices | 2 | ✔ |
| NOTIF-4 | Push recipients silently truncated at 2000 | 1 | ✔ |
| LOG-1 | PII (email, student name) reaches Crashlytics | 1 | ✔ |
| ROUTE-2 | No deep-link / refresh restoration | 2 | ☐ |
| STATE-3 | Sign-out can hang on the unregister callable | 1 | ✔ |
| SEC-2 | App Check off by default | 0/1 | ⚑ |
| SEC-3 | OTP: victim lock-out, IP source, no TTL | 3 | ☐ |
| SEC-4 | `feeDueReminders` global scan, silent cap | 2 | ☐ |
| CFG-4 | No Content-Security-Policy | 3 | ☐ |
| CFG-6 | Missing staff composite indexes | 2 | ☐ |
| CFG-7 | CI hardening (permissions, pinning, timeouts) | 3 | ☐ |
| DEP-1 | Functions dependency advisories (firebase-admin 12) | 2 | ☐ |
| PERF-1 | Finalise results: per-student attendance reads | 2 | ☐ |
| PERF-2 | Refresh parent access sequential, no guard | 2 | ☐ |
| ACAD-6 | Scheduled announcements push immediately | 2 | ✔ |
| OPS-3 | No alert policies / budget alerts | 0 | ⚑ |
| OPS-4 | Single-document invoice/receipt counters | — | ⊘ |

## P3 — low
| ID | Title | Phase | Status |
|---|---|---|---|
| NOTIF-5 | Stale-claim takeover not atomic | 1 | ✔ |
| NOTIF-6 | Lock-screen content visibility | 3 | ⊘ |
| NOTIF-7 | `ALL` pushes to staff who cannot open the notice | 3 | ⊘ |
| ACAD-5 | NaN / multi-decimal marks components pass client validation | 2 | ☐ |
| STATE-4 | `addReadIds` lost update | 2 | ☐ |
| STATE-5 | Small lifecycle gaps (marks submit, conversation, generate dialogs) | 3 | ☐ |
| STATE-6 | Late `switchBranch` overwrites tenant after sign-out | 2 | ☐ |
| ROUTE-1 | Three routes missing from `requiredPermissions` | 3 | ☐ |
| LOG-2 | Raw `debugPrint` of callable error bodies in release | 3 | ☐ |
| CFG-5 | `storage.cors.json` `origin:*` | 3 | ⚑ |
| CFG-9 | `.gitignore` lacks key/cert/service-account patterns | 3 | ☐ |
| CFG-3 | Android `allowBackup` default; INTERNET permission check | 3 | ☐ |
| CFG-10 | No `PrivacyInfo.xcprivacy`; shared app id dev/prod | 3 | ⊘ |
| SEC-6 | SVG uploads allowed; no self-signup spam control | 3 | ☐ |
| PERF-3 | Bulk import one query per row | 3 | ☐ |
| CFG-8 | CI builds `main.dart` not prod entry; no Android job; no dependabot | 3 | ☐ |

## Potentials / unknowns (verify first, fix only if reproduced)
| ID | Title | Status |
|---|---|---|
| ACAD-8 | Finalise can freeze stale marks | ? |
| ACAD-10 | Leave day-locks not required by create rule; client clock in decisions | ? |
| ACAD-11 | Timetable not re-validated after slot changes | ? |
| ACAD-12 | Homework `dueAt` time zone | ? |
| ACAD-13 | Holiday duplicate by double tap; working-day history client-side | ? |
| ACAD-14 | Grade from rounded percentage; absent policy (confirm intent) | ⊘ |
| ACAD-15 | Staff status change non-atomic | ? |
| STATE-7 | Firestore persistence not cleared at sign-out | ? |
| — | `registerDevice` non-transactional token move | ? |
| — | Push `quota-exceeded` treated as permanent | ? |
| — | Financial client-clock dates (`paymentDateKey`, `issueDateKey`, `reversalDateKey`) | ⊘ |

## Owner actions (not codeable from the repo)
OPS-1 enable PITR + scheduled backups + one restore drill · OPS-2 Crashlytics Gradle plugin / iOS symbol upload need an Android/Xcode build environment (runbook in `docs/app-check-and-monitoring.md`) · OPS-3 alert policies · SEC-2 App Check registration + enforcement · CFG-5 apply/restrict bucket CORS · create the staging project · signing keystore, Apple certificates, APNs key, VAPID key, Meta secrets · rules `--dry-run` on dev/prod · enable TTL policies in the console · run `firebase deploy` of indexes before the app that needs them.
