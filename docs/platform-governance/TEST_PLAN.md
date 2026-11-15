# Test plan

Principles: pure rule functions get unit tests; every new callable gets allow/deny/idempotency/tenant-isolation tests with the fake Firestore; every rules change gets allow **and** deny emulator tests
with mutation checks; Flutter screens get widget tests at phone/tablet/desktop and text scale 1.5; no phase is complete without green tests.

| Area | Tests |
|---|---|
| Lifecycle | new school INACTIVE; table-driven valid/invalid transitions; owner-only; school/branch admin cannot activate (callable and direct Firestore write); idempotent replay; history + audit + notification written together; CLOSED terminal; break-glass needs two owners |
| Access engine | matrix of lifecycle x subscription x grace x feature x role -> reason code; every school role blocked when inactive/suspended/expired/closed; platform admin never blocked; direct route and direct callable bypass attempts |
| Subscription | future start, valid, expired, grace (0 and N days), cancelled, renew, extend, invalid ranges, **time-zone boundaries** (end-of-day in the school zone, DST zones, UTC+14/-12), scheduler retry and duplicate-notification prevention |
| Features | enable/disable per school; one school only; direct route; direct callable; dependency validation both ways; data preserved; defaults do not overwrite overrides; trigger reversal for a direct-write module |
| Audit | schema validation; allowlist and redaction; no secrets; server timestamp; actor and school/branch correct; T1 transaction consistency (rollback removes the event); T2 duplicate trigger delivery does not duplicate; immutability (no client rules, no update path); pagination/filter/bounded range; export cap and self-audit |
| Cross-application | one scenario per app (platform, school admin, branch admin, teacher, parent, web, public portal, functions, scheduler) asserting the coverage matrix row |
| Security | malicious direct Firestore requests to every new collection; cross-tenant reads through every new callable; MFA required; forged client event rejected/labelled |
| Regression | full existing suites: Flutter, functions, rules (source and built), tool tests; school provisioning, login, student/parent/teacher, attendance, fees, notifications, homework, announcements, leave, academic, themes |

## Executed
Phase 12 results are in `SECURITY_TEST_REPORT.md`. Test files: `governance_security.test.js`, `index_exports.test.js`, `features.test.js`, `feature_guard.test.js`, `subscriptions.test.js`, `subscription_enforcement.test.js`, `school_notifications.test.js`, `audit.test.js`, `access_engine.test.js`; `firestore-tests/governance-rules.test.mjs`; Flutter widget and domain tests for each phase.
