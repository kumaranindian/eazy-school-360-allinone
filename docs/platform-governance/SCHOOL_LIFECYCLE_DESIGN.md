# School lifecycle design

## States and transitions (validated server-side only)
`INACTIVE, ACTIVE, SUSPENDED, EXPIRED, CLOSED`

| From | To | Who | Needs |
|---|---|---|---|
| (new) | INACTIVE | system | always the creation state |
| INACTIVE | ACTIVE | owner | remarks; policy D2/D5 checks (a school may be activated with no subscription only if the plan policy allows) |
| ACTIVE | SUSPENDED | owner | reason |
| SUSPENDED | ACTIVE | owner | remarks |
| ACTIVE | EXPIRED | scheduler (subscription ended, grace over) | automatic, system actor |
| EXPIRED | ACTIVE | owner or scheduler on renewal | subscription valid again |
| INACTIVE / ACTIVE / SUSPENDED / EXPIRED | CLOSED | owner | reason; an **APPROVED offboarding** (a second owner already approved it); the offboarding is then COMPLETED |
| CLOSED | INACTIVE | **recovery only** (`request/approve/cancelSchoolRecovery`) | written reason of 15+ characters; approval by a DIFFERENT owner; the school is INACTIVE afterwards and still needs the normal activation. Never straight to ACTIVE |
| any | INACTIVE | owner (deactivate) | reason |
Anything not in the table is refused (`INVALID_TRANSITION`). A client-supplied status is never trusted: the only writer of `status` is the
lifecycle service; the rules already refuse every client write to `schools.status`.

## Operation contract
`transitionSchool(schoolId, toStatus, {reason, remarks, internalNotes, message}, idempotencyKey)`:
authorise (platform owner, MFA) -> read school in a transaction -> validate transition -> write school fields (`lifecycleStatus` is the existing
`status`; `activatedAt/By`, `suspendedAt/By`, `closedAt/By`, `lifecycleUpdatedAt/By`) + one `schoolLifecycleHistory` entry + the audit event + the
outbox notification record **in one batch** -> mirror fan-out to profiles -> recipients notified. Replaying the same idempotency key returns the first result.

## Effective access
`effectiveAccess = f(lifecycle, subscription, grace)` is computed by the access engine (see SUBSCRIPTION_DESIGN) and mirrored on each profile as
`schoolAccess` (absent when allowed, else a reason code). The rules and Storage rules already check that field; callables call the engine.

## User-facing behaviour
All school roles (owner, branch admin, teacher, finance, parent) see the same screen: *"Account is inactive. Please contact admin@avail404.com."* (wording per
state; the address comes from `platformSettings/app`). Never reported as bad credentials; no dashboard navigation; only support-contact and sign-out actions.
Platform admins are never affected. Data is never deleted by a status change.

## As built (Phase 1)
`functions/school_lifecycle.js`: the `TRANSITIONS` table, `transitionSchool` (callable `transitionSchool`, owner + MFA, idempotency key, remarks/internal notes/message, reason rules, closure needs an approved
offboarding), recovery (`requestSchoolRecovery`, `approveSchoolRecovery`, `cancelSchoolRecovery`; collection `schoolRecovery/{schoolId}`), `schoolLifecycleHistory` (one entry per change including creation),
the audit event per transition (`SCHOOL_ACTIVATED/DEACTIVATED/SUSPENDED/REACTIVATED/EXPIRED/CLOSED/RECOVERED`, `SCHOOL_CREATED`). The old `setSchoolStatus` is a thin wrapper kept for the deployed app.
`createSchoolWithAdmin` creates the school INACTIVE and its first admin paused. Self-registration: the rules accept a client-created school only as INACTIVE; a trigger (`schoolCreated`) pauses its users immediately
and the app also pauses on the school document itself, so there is no window. The mirror `users.schoolAccess` now carries the state (`INACTIVE|SUSPENDED|EXPIRED|CLOSED`). EXPIRED is reachable only by the system actor (Phase 6 scheduler).
The app shows a per-state branded screen to every school role with the fixed support address and a "Contact support" action.
