# Implementation plan

## 0. Decisions taken
| # | Decision | Date |
|---|---|---|
| D1 | **Yes**: every new school starts INACTIVE, including self-registration (rules + app change). | 2026-11-14 |
| D10 | **Add recovery** for CLOSED schools: a written reason, approval by a DIFFERENT owner, result INACTIVE (then the normal activation). | 2026-11-14 |
| D12 | **Fixed**: the support address `admin@avail404.com` is a constant, not an editable setting. | 2026-11-14 |
Open: D2-D9, D11, D13, D14 below (needed from Phase 5 on; recommendations stand until answered).

## 1. Decisions (the request leaves these open; each has a recommendation)

| # | Question | Recommendation | Blocks |
|---|---|---|---|
| D1 | **Decided yes.** Self-registered schools start INACTIVE, so a new owner registers, then waits for activation. Needs a rules change and an **app release** (old apps would still try to create ACTIVE schools and be refused). | Yes, as specified. Existing schools are untouched. Ship the app first, rules last. | Phase 1 |
| D2 | Existing prod schools have no subscription. | They keep working: "no subscription document" = **legacy, access allowed** until a platform admin gives them a subscription. Never block on missing data. | Phase 6 |
| D3 | Expiry boundary and timezone. | Access is valid through the **end of the end date in the school's own time zone** (23:59:59.999). Not-started until 00:00 of the start date. | Phase 5 |
| D4 | Grace period. | Per-subscription `gracePeriodDays`, default **0** (no automatic grace). During grace, access is allowed and admins see a warning. | Phase 5 |
| D5 | Consistency window for time-based expiry. The rules can only read the mirrored profile flag; they cannot read the subscription (size limit). | A scheduler runs every **15 minutes** and mirrors the effective state; lifecycle/feature/subscription *changes by an admin* apply within seconds (fan-out). Callables check the live subscription on every call. Documented maximum staleness for rules-level checks: 15 minutes. | Phase 6 |
| D6 | Feature enforcement for modules whose writes go straight to Firestore (attendance, fees, students, homework...). Per-module rule clauses do not fit in the rules. | Enforce by **UI + routes + callables**, plus a **trigger** that flags/reverts writes to a disabled module and audits the attempt. Migrating a module's writes to callables is a separate, per-module project (priced after Phase 8). Accept that a determined user with a modified client could write to a disabled module until the trigger reverts it. | Phase 8 |
| D7 | Audit of client-written modules will be **after the fact** (Firestore triggers read `createdBy/updatedBy`, which the rules guarantee). | Accept. Allowlist the collections in the catalogue; cost is one function invocation and one write per audited business write. | Phase 10 |
| D8 | Failed logins, permission-denied and "profile viewed" cannot be captured server-side. | Accept: login success/failure via Identity Platform blocking functions (success) and **client-reported, rate-limited, clearly untrusted** events (failure); no per-view auditing except exports/downloads. | Phase 9 |
| D9 | Audit retention and volume. | Default **400 days online**, then archive to cold storage (Cloud Storage export) for 7 years where the school's jurisdiction requires it; partition collection by month. Confirm retention with your legal advisor. | Phase 9 |
| D10 | CLOSED is terminal. Is there any recovery? | **Decided: two-owner recovery** (request with reason, a different owner approves, school returns INACTIVE). | done |
| D11 | Plan catalogue: who defines plans, any pricing in code? | `platformPlans` collection managed by owners; **no prices or currencies in code**; a plan is a name, a period type and an optional default feature set. | Phase 5 |
| D12 | Support email `admin@avail404.com` in messages. | **Decided: fixed constant (`lib/core/config/support_contact.dart`), not editable.** | done |
| D13 | Existing `schools.features` and `platformBilling`. | Migrate `features` into the new feature configuration (keeping the same keys); keep `platformBilling` as the money ledger, separate from entitlements. | Phase 7 |
| D14 | May a school admin see their own school's audit history? | Default **off**; a later, explicit, read-only view of lifecycle/subscription/feature events only. | Phase 11 |

**Phases 1-4 are unblocked (D1, D10, D12 decided).** D2-D5 are needed before Phase 5/6; D6-D9 before Phase 8-10. Say "confirm all
recommendations" to proceed with every default.

## 2. Phases (revised for what already exists)

| Phase | Scope | Builds on |
|---|---|---|
| 0 | Assessment and these documents | done |
| 1 | Lifecycle backend: statuses EXPIRED/CLOSED, validated transition table, `schoolLifecycleHistory`, activation remarks and message, default INACTIVE (server-created now; self-registration after D1 app release), idempotency keys | `school_lifecycle.js` |
| 2 | Central access engine: one `evaluateSchoolAccess` with reason codes, used by every callable; mirror carries the reason; branded inactive/suspended/expired/closed screen with the support email | `access.js`, `schoolAccess` mirror |
| 3 | Platform console: activation management (search by name/id/owner, registration-date and status filters), school detail tabs, lifecycle history | existing console |
| 4 | (done) Notifications: `platformNotifications` per recipient with created/delivered/acknowledged states, modal with acknowledge/dismiss, inbox, offline-safe | `platformNotices`, FCM infra |
| 5 | Subscriptions: plans, subscription, history, dates/grace/renew/extend/cancel/trial, validation, tests for time-zone boundaries | new |
| 6 | Subscription enforcement: 15-minute scheduler (idempotent, no duplicate notices), mirror, live check in callables, access matrix | Phase 2 |
| 7 | Feature catalogue (actual modules), dependencies, global defaults, per-school overrides, history | `schools.features` |
| 8 | Feature enforcement: UI/routes, callables, trigger-based reversal and audit for direct-write modules (per D6) | Phase 7 |
| 9 | Audit architecture: schema, trusted writer, partitioned storage, redaction allowlists, read path through callables, retention | `platformAuditLog` |
| 10 | Instrumentation, module by module, with the coverage matrix kept honest (`AUDIT_EVENT_COVERAGE.md`) | Phase 9 |
| 11 | Audit dashboards: global, school, user, security, history views, bounded CSV export that audits itself | Phase 9 |
| 12 | Security and regression: tenant-isolation, malicious direct requests, cross-role matrix | all |
| 13 | Dev deployment, migration dry-run, rollback, readiness assessment | all |

No phase is marked complete without its tests; nothing is deployed to production without explicit approval.
