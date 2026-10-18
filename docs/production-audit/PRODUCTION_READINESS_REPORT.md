# EazySchool 360 — Production readiness report

Commit audited: `develop` @ `f36c35f` · Date: 2026-10-17 · Auditor: Claude (lead) with four read-only sub-audits (findings tagged L/S in BUG_REGISTER.md).

## 0. Re-assessment after remediation (HEAD of `develop`, 2026-10-18)

**Verdict: still NOT READY — but the blockers have changed character.** Every code-level P1/P2 finding is fixed with a regression test (see FIX_TRACKER.md, TEST_RESULTS.md "Post-fix verification"). What stands between this code and production is now **verification on real infrastructure and operations**, none of which can be done from the repository.

| # | Gate | Was | Now | What decides it |
|---|---|---|---|---|
| 1 | Authentication & session | PARTIAL | **PARTIAL** | code fixed (NOTIF-1, STATE-3, ROUTE-2); App Check / OTP abuse controls need enforcement (SEC-2/3 ⚑) |
| 2 | Role-based authorization | PARTIAL | **PARTIAL** | rules + 457 tests green on source and built artifact; ACAD-9 enrolment check not feasible in rules (accepted residual); live ruleset unknown |
| 3 | Multi-tenant isolation | PARTIAL | **PARTIAL** | proven in emulator only |
| 4 | Firestore & Storage rules | FAIL | **UNKNOWN → blocker until dry-run** | release artifact is 147,884 B (56 % of limit, CI gate at 85 %); must still pass `tool/deploy_rules.sh <project> --dry-run` on dev and prod |
| 5 | Student & staff data integrity | PARTIAL | **PARTIAL** | ACAD-2/7, UI-1 fixed; admission-number reservations need the backfill (`tool/backfill_admission_numbers.js`) and duplicates resolved by a human |
| 6 | Attendance, leave, holidays, results | FAIL | **PARTIAL** | ACAD-1/3/4, UI-2 fixed; existing year dates need `tool/migrate_year_dates.js` |
| 7 | Fees, invoices, payments | PARTIAL | **PARTIAL** | unchanged: design sound, no E2E, client-clock dates (⊘) |
| 8 | Notification reliability & isolation | FAIL | **PARTIAL** | retry/redrive, no truncation, device clean-up, disabled-login gating done and unit-tested; never run against real FCM/APNs |
| 9 | Critical end-to-end workflows | UNKNOWN | **UNKNOWN** | no journey run against a real project |
| 10 | Static analysis & tests | PASS | **PASS** | format, analyze, 1,481 Dart, 155 functions, 24 tool, 457 rules ×2, TZ ×3 |
| 11 | Production configuration | FAIL | **FAIL** | CFG-1 guard, CI hardening, Android build job added; no staging project, App Check, signing keystore, APNs/VAPID/Meta secrets |
| 12 | Backup & restoration | UNKNOWN | **UNKNOWN** | PITR + scheduled backups + one restore drill (OPS-1) |
| 13 | Monitoring & incident recovery | FAIL | **FAIL** | LOG-1 fixed; Crashlytics native setup and alert policies are owner work (OPS-2/3) |
| 14 | Build, deployment & rollback | PARTIAL | **PARTIAL** | prod-entry web build in CI; Android/iOS builds never run here |

### Risks introduced by the fixes themselves (read before deploying)
1. **Deploy order for admission numbers.** The new rules *require* a reservation on student create. An old app build cannot admit students once the rules are live. Ship the app first (or together), run the backfill, then deploy rules.
2. **Untested in a real toolchain:** the Gradle release-signing guard (no Android SDK here — only pinned by a text test), the `firebase-admin@13` upgrade (unit tests only; deploy to dev and call each callable), the new CI `android` job and prod-entry build (never run on a runner), TTL policies and the new `pushDeliveries` index (take effect on index deploy).
3. **CSP is Report-Only** by design until watched on the dev site.
4. **Data migrations are one-way in effect.** Year-date migration needs the correct IANA zone per school; take a backup first (which presupposes OPS-1).
5. **Accepted residuals:** ACAD-9 (enrolment not verifiable in rules), SEC-3 victim lock-out and SEC-6 signup spam (need App Check/CAPTCHA), ~40 unreviewed post-`await` `setState` calls (STATE-5, debug-mode only), PERF-3.

### Shortest path to READY
1. Create the **staging** project; deploy indexes, rules (`--dry-run` first on both projects) and functions there; smoke-test every callable (firebase-admin 13).
2. Enable **PITR + scheduled backups**; do one restore drill.
3. Run both **backfills** on staging copy of real data; resolve reported duplicates.
4. Configure **signing** (Android keystore, Apple certs, APNs, VAPID, Meta secrets) and produce one signed AAB/IPA; set up **Crashlytics** natively; create **alert/budget policies**; enable **App Check** (monitor, then enforce).
5. Run the **critical journeys** end to end on staging with real devices (admit → fees → payment → receipt; attendance; leave; marks → finalise → publish; push on Android/iOS; parent portal).
6. Watch CSP on staging, flip to enforcing; then promote in the order: app → backfills → rules → functions.

---

## 1. Verdict: **NOT READY FOR PRODUCTION**

The code base is unusually well engineered where it matters most — money, tenant isolation and role scoping are enforced server-side, transactional and heavily tested. It is not releasable because (a) the security ruleset may not be deployable, (b) a confirmed date defect corrupts academic-year boundaries for every school east of UTC, (c) push delivery leaks to the wrong person and silently loses messages, (d) release signing, monitoring and backups are not in place or not evidenced, and (e) no end-to-end journey has ever been exercised against a real environment. None of these needs a redesign; most are small, local fixes (see IMPLEMENTATION_PLAN.md).

## 2. Findings by priority (confirmed + highly likely)
| Priority | Count | Examples |
|---|---|---|
| P0 | **0** | no demonstrated cross-tenant exposure or privilege escalation |
| P1 | **6** (+1 unverified gate blocker) | SEC-1, NOTIF-1, NOTIF-3, ACAD-1, CFG-1, OPS-2 · OPS-1 (backups UNKNOWN) |
| P2 | **26** | STATE-1/2, UI-1/2, ACAD-2/3/4/7/9, NOTIF-2/4, LOG-1, ROUTE-2, SEC-2/3/4, CFG-4/6/7, DEP-1, PERF-1/2, ACAD-6, OPS-3/4 |
| P3 | **13** | see BUG_REGISTER.md |
Potentials and unknowns are listed separately in BUG_REGISTER.md §Potentials, PRODUCTION_GAP_REGISTER.md and the UNKNOWN cells of PRODUCTION_CONFIGURATION_AUDIT.md.

## 3. Five most serious defects
1. **SEC-1 — rules at the release-size edge.** 223,727 B; `tool/patch_dev_push_rules.js:19-37` records full releases being refused (+773 B refused, −1 B accepted). Every recent security rule may not be live.
2. **ACAD-1 — academic years off by one day.** Local-midnight storage vs. `.toUtc()` reads (`timetable_scope.dart:34`, `leave_scope.dart:33`, `substitution_pages.dart:85`, …); in IST the last day of the year is rejected for leave and balances/timetable ranges are cut. Existing data affected; the new school-year registry inherits it.
3. **NOTIF-1 — pushes follow the device, not the user.** Only the app-bar button unregisters the device (`app_shell.dart:420-423`); the account-inactive page, create-school page and server-side session revocation do not.
4. **NOTIF-3 — failed pushes are never retried.** FAILED and stuck PROCESSING claims are terminal; fee-due and absence alerts are silently lost.
5. **CFG-1 — debug-signed release fallback** (`build.gradle.kts:62-71`) with only a warning.
(Next: OPS-1 no backup evidence; ACAD-2 duplicate admission numbers; STATE-1 roster race; LOG-1 PII in Crashlytics.)

## 4. Race conditions & data integrity
Unsafe interactions confirmed: duplicate admission numbers (ACAD-2), partial marks save with unrecoverable retry (ACAD-3), `approvedSheets` read-then-write (ACAD-4), non-transactional student transfer (ACAD-7), roster paging/search races (STATE-1/2), read-ids lost update (STATE-4), stale-claim takeover (NOTIF-5), late `switchBranch` overwrite (STATE-6). **Verified safe:** payment collection, reversal, invoice generation and numbering, attendance register save, leave decisions and ledger, homework lateness, timetable publish, push claim. Details and tests: RACE_CONDITION_AUDIT.md.

## 5. Security & tenant isolation
Rules suite (437 tests) passes: default-deny, school/branch isolation, parent→linked children/class-section scoping, teacher→assigned sections, no client write to `role`/`schoolId`/`login`/`branchRoles`, per-branch roles ignore corrupt values, storage limits. Gaps: rules deployability (SEC-1), App Check off (SEC-2), attendance spoofing by a crafted write (ACAD-9), push to disabled logins (NOTIF-2), PII in crash logs (LOG-1), no CSP (CFG-4), functions dependency advisories (DEP-1), self-signup spam (SEC-6). No secrets in the tree. See SECURITY_AUDIT.md.

## 6. Critical journeys
Passed in automated tests only (not E2E): tenant/role access, payment collection/reversal, attendance save, leave decisions, marks state machine, homework lateness, branch transfer contract. Failed or defective: leave on the final day of the year (IST), results finalisation with silent attendance gaps, admission with unlinked guardian, roster loading, push after sign-out, deep-link restoration. **Not run:** every journey against a real project/device. See END_TO_END_FLOW_AUDIT.md.

## 7. Checks actually executed
Format ✔ · analyze ✔ · 1,432 Dart tests ✔ (60.9 % line coverage) · 132 functions tests ✔ · 437 rules/storage tests ✔ · prod web build ✔ (5.9 MB JS) · `npm audit` ✔ (findings). **Not run:** OSV (proxy), Android/iOS builds, rules dry-run deploy, E2E, load, TZ matrix, device push, secret-history scan, restore drill. See TEST_RESULTS.md.

## 8. Release gates
| # | Gate | Result |
|---|---|---|
| 1 | Authentication & session management | **PARTIAL — GAPS REMAIN** (NOTIF-1, ROUTE-2, OTP/App Check unverified) |
| 2 | Role-based authorization | **PARTIAL — GAPS REMAIN** (rules strong and tested; ACAD-9; deployed rules unknown) |
| 3 | Multi-tenant isolation | **PARTIAL — GAPS REMAIN** (proven in emulator on repo rules; live state UNKNOWN) |
| 4 | Firestore & Storage rules | **FAIL — RELEASE BLOCKER** (SEC-1) |
| 5 | Student & staff data integrity | **PARTIAL — GAPS REMAIN** (ACAD-2, ACAD-7, UI-1) |
| 6 | Attendance, leave, holidays, results | **FAIL — RELEASE BLOCKER** (ACAD-1; ACAD-3/4, UI-2) |
| 7 | Fees, invoices, payments, receipts | **PARTIAL — GAPS REMAIN** (design verified sound; client-clock dates, counter ceiling, no E2E) |
| 8 | Notification reliability & recipient isolation | **FAIL — RELEASE BLOCKER** (NOTIF-1, NOTIF-3) |
| 9 | Critical end-to-end workflow tests | **UNKNOWN — NOT VERIFIED** |
| 10 | Static analysis & automated tests | **PASS — VERIFIED** (analyze/format/3 suites green; dependency scan separately incomplete: DEP-1, OSV not run) |
| 11 | Production environment & release configuration | **FAIL — RELEASE BLOCKER** (CFG-1, no staging, App Check, signing/APNs/VAPID unverified) |
| 12 | Backup & restoration verification | **UNKNOWN — NOT VERIFIED** (blocker until PITR + one drill) |
| 13 | Monitoring, logging, incident recovery | **FAIL — RELEASE BLOCKER** (OPS-2, OPS-3, LOG-1) |
| 14 | Build, deployment & rollback readiness | **PARTIAL — GAPS REMAIN** (web build ✔; no deploy automation; mobile builds not verifiable here; rules rollback documented) |

Overall: critical gates failed or unverified → **NOT READY**.

## 9. Environments & scenarios not tested
Dev, staging (does not exist), UAT, production; real devices; deployed web; real FCM/APNs/WhatsApp; multi-school load; clock/time-zone variation; offline/lost-response behaviour; Firestore on-device cache on shared devices; data migration on real legacy data.

## 10. Release blockers, in order
B1 rules deployability · B2 academic-year dates · B3 push hygiene & redrive · B4 release signing guard · B5 backups/PITR + restore drill · B6 crash reporting & alerts · B7 staging + repeatable deploy · B8 E2E smoke on staging · B9 App Check (if phone login is used). Acceptance criteria per task: IMPLEMENTATION_PLAN.md.

## 11. Recommended sequence
Phase 0 (verification/infra, no code risk) → Phase 1 (blockers) → Phase 2 (integrity & visible defects) → Phase 3 (hardening) → Phase 4 (rehearsal on staging, then canary school). A pilot with one school, 1–2 trusted finance users and rules-only finance is reasonable once B1–B8 are closed.

## 12. Audit documents
`docs/production-audit/`: PROJECT_ANALYSIS · FEATURE_READINESS_MATRIX · BUG_REGISTER · RACE_CONDITION_AUDIT · SECURITY_AUDIT · FIREBASE_DATABASE_AUDIT · END_TO_END_FLOW_AUDIT · PERFORMANCE_AUDIT · TEST_RESULTS · PRODUCTION_CONFIGURATION_AUDIT · PRODUCTION_GAP_REGISTER · IMPLEMENTATION_PLAN · DEPLOYMENT_CHECKLIST · PRODUCTION_READINESS_REPORT.

## 13. Limits of this audit
Sub-audit findings tagged **S** were read by delegated agents and not all re-verified by the lead; each will be reproduced by its regression test before being fixed. Coverage of the 480 Dart files was by targeted search and reading, not line-by-line. No application code, rules, infrastructure or configuration was changed by this audit (documents only); CHANGELOG.md and CLAUDE.md were not touched.
