# Readiness assessment (end of Phase 13)

Date: 2026-11-14. Branch `feature/invoice-genetration-fees-wise`. **Nothing is committed, nothing is deployed.**

## Verdict
| Target | Verdict |
|---|---|
| Deploy to **dev** | **Ready, after four things** that need a person: (1) enable MFA on the dev project and create a dev platform owner; (2) run the read-only dry run on dev; (3) decide whether to run the pre-existing admission-storage check first; (4) approve the dev deploy. |
| Deploy to **prod** | **Not yet.** Needs a successful dev run plus the decisions and work in "Before production" below. |

## Evidence
| Area | Evidence |
|---|---|
| Phases 0-13 | all implemented; per-phase summaries and reports in `IMPLEMENTATION_STATUS.md` |
| Automated tests | Flutter 2,471 pass; functions 691 pass (1 skipped); tools 40 pass; Firestore rules 564 of 565 on the source and on the built artifact |
| Static checks | `flutter analyze` clean; `dart format` clean; `index.js` loads (a test); every function name, trigger path and region validated offline (`deploy_manifest.test.js`) |
| Security | `SECURITY_TEST_REPORT.md`: cross-role matrix, hostile-payload fuzzing, tenant isolation, rules default-deny (mutation-checked); four defects found and fixed |
| Data impact | read-only dry run tool (`tool/governance_dry_run.js`) with its own tests; additive data model; no backfill needed |
| Rollback | written and per-step (DEPLOYMENT_GUIDE section 5), including a kill switch for subscription enforcement |

## What was NOT verified (cannot be, without the real environment)
- The functions were never deployed or run behind the real callable layer (App Check, quotas, IAM, cold starts, scheduler permissions). The emulator could not be used for a discovery run here because another emulator session was already using its ports; the offline manifest checks cover what Firebase validates on deploy.
- The **compiled Firestore rules size** after the one-line change: only a real dev release can show it. The margin is thin; the previous experience was a refused release.
- Composite index build time and the cost of the 20 `moduleWatch_*` triggers on real traffic.
- Behaviour on iOS (no iOS device or build was exercised).
- Penetration testing, load testing, monitoring/alerting (none created).

## Open items
| # | Item | Owner | Blocks |
|---|---|---|---|
| 1 | Dev project has no MFA enabled (platform admin flows need it) | you | dev smoke test |
| 2 | `admission-storage-rules` #36 fails in the emulator (second upload to the same path succeeds). Predates this work (from `develop`). Verify on dev with a real second upload | you / next session | confidence in "create-only", not the rollout |
| 3 | D9: audit retention (400 days online, 7 years cold) and **deletion stays off**; confirm with legal. Also: audit records and account deletion (matrix row D4f is PENDING) | you + legal | prod |
| 4 | D6: direct writes to a disabled module are recorded, not reverted. Decide if revert-on-violation or per-module migration to callables is wanted | you | not blocking |
| 5 | The app does not send client-reported audit events (logout, expired session, permission denied) yet; the callable is ready | next session | not blocking |
| 6 | Audit gaps: academic setup collections, admission documents/fees/conversions, branding/regional changes, notification acknowledgement/delivery are not in the central trail (AUDIT_EVENT_COVERAGE.md) | next session | not blocking |
| 7 | Rules-level allowlist for client-created school documents (closes the short window described in SECURITY_TEST_REPORT.md #4) and the "paused user may edit own profile" rule: both need rules size, so they need a measured dev release | next session | not blocking |
| 8 | Account-deletion processor does not yet remove `platformNotifications` (matrix D4d) and must keep `auditEvents` (D4f); the processor is OFF | you | enabling deletion |
| 9 | LOGIN_SUCCESS audit needs Identity Platform blocking functions (adds sign-in latency): needs approval. Failed sign-ins cannot be captured | you | not blocking |
| 10 | Cloud Monitoring alerts for the schedulers and trigger retries are not created | next session | prod |
| 11 | Android bundle for the new app version has not been built; iOS not built | next session | mobile release |
| 12 | Uncommitted work: ~85 changed/new files. Suggested commits (do not combine): (a) rules + rules tests, (b) functions lifecycle/access/notifications, (c) functions subscriptions + features + guard, (d) functions audit + indexes, (e) app (core, console, screens) with tests, (f) docs/tooling | you | everything |
| 13 | `mockUi/` is an untracked folder that predates this work; left alone | you | nothing |

## Decisions taken (all recorded in IMPLEMENTATION_PLAN.md)
D1 yes (new schools start INACTIVE), D10 recovery of CLOSED schools by a different owner, D12 fixed support address; D2-D9, D11, D13, D14 on the recommended defaults.

## Before production (in addition to everything above)
A green dev smoke test (DEPLOYMENT_GUIDE section 4) kept for a day (so the scheduler has run); dry run on prod with approval; items 3, 8 and 10 closed; mobile builds ready so the minimum-build step can be set; a communicated window; a backup taken immediately before.
