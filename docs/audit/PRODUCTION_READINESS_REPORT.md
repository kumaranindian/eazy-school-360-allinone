# Production readiness report - EazySchool 360

Audit date 2026-10-31 · branch `release/android-prod-prep` @ `e4b9016` · read-only audit (no source change, no deploy, no production data touched).

## Decision: CONDITIONALLY READY

Not production ready, and not safe to release to the Play Store as it stands, but also not "not ready": no critical security vulnerability was found, tenant isolation and the money path are well enforced and well tested, and the application is broad. Several important, fixable issues must close first: a red test suite, no verified backup, no privacy policy, no end-to-end testing, a duplicate-creating import path and App Check not enforced. After those, it is suitable for a **controlled pilot with documented limitations** (no online payment, no late fees or instalments, no promotion workflow, Android-only push).

**Overall readiness: 61 %** (judgement composite: 50 % feature score 72 %, 50 % mandatory-gate score 50 %; method below). Treat it as a way to compare with later audits, not as a probability.

## Headline numbers
| Measure | Value |
|---|---|
| Modules audited | 13 (plus repository, rules, Functions, Storage, deployment) |
| Features audited | 122 |
| PASS | 70 |
| PARTIAL | 35 |
| FAIL | 2 |
| NOT IMPLEMENTED | 11 |
| NOT TESTED | 4 |
| Critical security findings | 0 |
| Production blockers | 3 (PB-01, PB-02, PB-03); 5 more High items |

## What was run
| Check | Result |
|---|---|
| `flutter analyze` | no issues |
| `dart format --set-exit-if-changed lib test` | clean |
| `flutter test` (full) | **1665 tests: 1659 pass, 6 fail** (all `branding_shell_test`, PB-01) |
| Contract tests (communication, exams) | pass |
| Rules suite, serial, built artifact | 479 / 479 pass |
| Functions tests | 251: 250 pass, 1 skipped |
| Deletion processor emulator test | 1 / 1 pass |
| Tooling tests | 24 / 24 pass |
| OSV (Dart) | 0 advisories / 137 packages |
| `npm audit --omit=dev` | 1 high, 10 moderate, 0 critical |
| Firebase CLI (read-only): functions list dev/prod | 43 deployed on each; all 40 exports present |
| Not run | integration/e2e (none exist), load tests, browser/device runs, anything against prod data |

## Mandatory gates
| Gate | Status | Basis |
|---|---|---|
| No known critical security vulnerability | Met | none found (see `SECURITY_AUDIT.md`) |
| Verified tenant isolation | Met in repository | 479 rules tests incl. sweeps; **not** probed on the deployed rules (PB-07) |
| Correct role-based authorization | Met, one weakness | PB-10 photo reads |
| Critical business workflows successfully tested | **Partly** | covered by fakes + contract tests; never end-to-end (PB-04) |
| Financial calculations validated | Mostly met | money rules and planners tested; no reconciliation job or live data check |
| No critical data-integrity issues | **Not tested** | no production data inspected; PB-05 can create duplicates |
| Production configuration verified | **Partly** | functions deployed and matching names; rules/storage/Auth/App Check/CSP not confirmed (PB-06, PB-07, PB-12) |
| Backup and recovery plan established | **Not met** | PB-02 |
| Critical automated tests passing | **Not met** | 6 failing tests (PB-01) |

Gate score: met = 1, partial/mostly = 0.5, not met/not tested = 0 → 4.5 / 9 = 50 %.

## Feature-wise readiness
Module score = (PASS + 0.5 × PARTIAL) / features.

| Module | Features | PASS | PARTIAL | FAIL | NOT IMPL. | NOT TESTED | Score |
|---|---|---|---|---|---|---|---|
| Authentication & Users | 11 | 5 | 6 | 0 | 0 | 0 | 73% |
| School Management | 9 | 7 | 2 | 0 | 0 | 0 | 89% |
| Student Management | 13 | 8 | 3 | 1 | 1 | 0 | 73% |
| Parent Management | 5 | 4 | 1 | 0 | 0 | 0 | 90% |
| Fee Management | 20 | 13 | 4 | 0 | 3 | 0 | 75% |
| Attendance | 10 | 6 | 3 | 0 | 1 | 0 | 75% |
| Timetable | 7 | 6 | 1 | 0 | 0 | 0 | 93% |
| Homework | 7 | 6 | 1 | 0 | 0 | 0 | 93% |
| Examinations & Results | 9 | 7 | 2 | 0 | 0 | 0 | 89% |
| Communication & Notifications | 8 | 4 | 1 | 0 | 3 | 0 | 56% |
| Leave | 4 | 3 | 1 | 0 | 0 | 0 | 88% |
| Reports & Dashboards | 8 | 0 | 6 | 0 | 2 | 0 | 38% |
| Platform, Operations & Compliance | 11 | 1 | 4 | 1 | 1 | 4 | 27% |
| **All** | 122 | 70 | 35 | 2 | 11 | 4 | 72% |

Full per-feature evidence: `FEATURE_AUDIT_MATRIX.md`.

## Critical findings
None. No finding allows cross-tenant access, privilege escalation or unauthorised money movement in the repository rules.

## High-priority findings
- **PB-01** Red test suite: the always-visible Help icon pushes the header title 72 px off-centre at 390 px (6 failing tests).
- **PB-02** No evidence of backups/PITR/restore (data-loss risk for a school system).
- **PB-03** No privacy policy (blocks Play listing; children's data).
- **PB-04** No end-to-end or load tests.
- **PB-05** Sheet re-upload duplicates students.
- **PB-06** App Check not enforced on deployed prod callables.
- **PB-07** Deployed prod functions differ by hash from dev; deployed rules/Storage not provably equal to the repo.
- **PB-08** Account deletion processor off and never run on real data.

## Medium and low findings
- Medium: PB-09 dependency advisories (1 high, 10 moderate in Functions), PB-10 branch-wide photo reads and token URLs, PB-11 absent capabilities (late fees, instalments, online payment, promotion, student report, finance dashboard), PB-12 CSP report-only.
- Low: PB-13 open school creation, PB-14 no idle timeout / app-only forced password change, PB-15 per-branch counter throughput, PB-16 stale docs (they say prod cannot deploy functions; it has).

## Security vulnerabilities
See `SECURITY_AUDIT.md`. Summary: none critical; PB-06, PB-10, PB-09, PB-12, PB-13, PB-14 are the actionable weaknesses.

## Performance issues
No measured bottleneck and **no load test**. Estimated hot spots: per-branch numbering counters, sequential bulk loops, rules lookup reads, hourly scheduled scans. See `PERFORMANCE_AUDIT.md`.

## Missing functionality (against the audit brief)
Late fees · instalments · online payment · year-end promotion · leave as an attendance status · student report · finance dashboard · exam-timetable screen (dates exist per subject) · WhatsApp/email/SMS notifications · web push · privacy policy. Teacher "availability" is only conflict checking.

## Deployment blockers
PB-01, PB-02, PB-03 are the blockers. PB-06 to PB-08 should be closed before real schools are onboarded.

## Data integrity audit
Not performed against data (read-only; no production access by design). Code-level controls found: deterministic ids and create-only reservations (admission numbers, invoice/receipt numbers, payments), transactional registers and leave decisions, idempotent invoice generation, reversal-only payment changes. Needed before pilot: a read-only integrity script run against the dev data and later prod (duplicates, orphan links, invoice balance vs payments via `InvoiceReconciler`).

## Differences between development and production (observed)
- Functions: same names and region; **different source hashes** (PB-07). Both lack `ENFORCE_APP_CHECK`; both have OTP variables empty (OTP off) and deletion processing off.
- Hosting: dev is live at `eazy-school-360-dev.web.app` from this branch; prod web hosting was not verified.
- Firebase options/config files exist for both; `docs` still describe prod as unable to deploy functions (PB-16).
- Android: release signing requires `android/key.properties`; target SDK 36, min SDK 24, `allowBackup=false`, only INTERNET and POST_NOTIFICATIONS permissions.

## Recommended implementation sequence
1. Fix PB-01 and keep the whole suite green (hours).
2. Enable PITR/backups on prod and rehearse a restore (PB-02).
3. Publish the privacy policy and link it (PB-03).
4. Redeploy prod from `HEAD` after dry-runs; confirm rules, Storage, Auth providers, authorized domains (PB-07); update the stale docs (PB-16).
5. Ship App Check and enforce it (PB-06).
6. Add duplicate protection to sheet upload (PB-05).
7. Script the five workflows against dev and run them (PB-04); then a load rehearsal.
8. Rehearse and enable account deletion (PB-08).
9. Dependency fixes and CSP enforcement (PB-09, PB-12); photo-read hardening (PB-10).
10. Decide scope for late fees / instalments / online payment / promotion with the pilot school (PB-11).

## Honest limits of this audit
- Read-only and static for deployed state; prod rules and Storage settings were not readable without a deploy.
- Workflows are verified by automated tests with fakes and emulator rules, not by a person driving the app.
- Visual and device behaviour (PDF layout, push on a phone, browser variants, accessibility with a screen reader) was not exercised.
- Prior audit documents in `docs/production-audit/` were used only as leads; every status above was re-derived from code or output from this session.
- During the audit I accidentally stashed and immediately restored the user's uncommitted `CLAUDE.md` edits; they were restored exactly (same diff statistics) and nothing was lost.
