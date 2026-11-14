# Audit event coverage matrix (as of Phases 9-11)

Everything below lands in the central trail `auditEvents/{yyyyMM}/events/{eventId}` through the single writer `functions/audit.js`.
**Trust**: T1 written with the change (callable), T2 observed afterwards by a trigger (actor taken from the rules-enforced `createdBy`/`updatedBy`),
T3 system job, T4 reported by the app (NOT proof). "Done" = implemented and covered by tests in this repository.
**Honest limit of the platform audit mirror:** platform, lifecycle, subscription and feature events are first written (T1, in the same transaction as the
change) to `platformAuditLog`, and a trigger copies them into the central trail a moment later. If the copy fails it is retried; the original record is never lost.

| Area | Event types | How captured | Trust | Status | Notes |
|---|---|---|---|---|---|
| PLATFORM | platform admin created / role / status, support access granted / revoked, billing, notices, app requirements, offboarding | `platformAuditLog` -> `auditMirrorPlatform` | T1 (mirrored) | **Done** | category from the action name; unknown actions fall back to PLATFORM |
| SCHOOL | SCHOOL_CREATED / ACTIVATED / DEACTIVATED / SUSPENDED / REACTIVATED / CLOSED / RECOVERED, recovery request / cancel | `transitionSchool`, recovery callables -> mirror | T1 | **Done** | |
| SCHOOL | SCHOOL_EXPIRED / SCHOOL_REACTIVATED by the scheduler | `systemTransition` -> mirror | T3 | **Done** | source SCHEDULER, application SCHEDULER |
| SUBSCRIPTION | SUBSCRIPTION_SET / EXTENDED / RENEWED / CANCELLED / TRIAL_GRANTED, PLAN_SAVED | `subscriptions.js` -> mirror | T1 | **Done** | the scheduler's status changes are in `schoolSubscriptionHistory` only |
| FEATURE | SCHOOL_FEATURES_CHANGED, FEATURE_DEFAULTS_CHANGED | `features.js` -> mirror | T1 | **Done** | |
| FEATURE | FEATURE_ACCESS_DENIED | `moduleWatch_*` -> `feature_guard` -> mirror | T2 | **Done** | recorded, not blocked or reverted |
| AUTHENTICATION | login access changed, password reset, provisioning, branch access (everything written to `schools/{s}/authAudit`) | `authAudit` -> `auditMirrorAuth` | T1 (mirrored) | **Done** | type name comes from the existing record |
| AUTHENTICATION | LOGOUT, SESSION_EXPIRED | `reportClientEvent` | T4 | **Callable done; the app does not send it yet** | wiring the app is a separate, small step |
| SECURITY | PERMISSION_DENIED_UI | `reportClientEvent` | T4 | **Callable done; the app does not send it yet** | |
| SECURITY | AUDIT_LOG_VIEWED, AUDIT_LOG_EXPORTED, AUDIT_MONTH_ARCHIVED, AUDIT_MONTH_PURGED | `audit.js` | T1 / T3 | **Done** | the first page of a search is audited, later pages are not |
| AUTHENTICATION | LOGIN_SUCCESS | identity blocking function | | **Not built** | needs Identity Platform blocking functions and your approval (adds sign-in latency) |
| AUTHENTICATION | LOGIN_FAILED | | | **Not capturable** | Firebase Auth rejects the attempt before any of our code runs; there is no session to report from |
| STUDENT / PARENT / STAFF | `*_CREATED` / `*_UPDATED` / `*_DELETED` for students, parents, staff | `moduleWatch_*` | T2 | **Done** | values only for allow-listed fields (status, class, section, ...); phone, e-mail, address, guardian etc. are recorded as "changed" |
| ATTENDANCE_LEAVE | attendance sessions, staff attendance days, leave applications | `moduleWatch_*` | T2 | **Done** | per-student attendance marks are NOT audited one by one (volume); the session is |
| FEES | fee structures, invoices, payments | `moduleWatch_*` | T2 | **Done** | amounts and receipt numbers are allow-listed; refunds/reversals/concessions are changes to invoices/payments |
| ACADEMIC | timetables, substitutions, homework and submissions, exams, marks sheets | `moduleWatch_*` | T2 | **Done** | classes, sections, subjects, holidays and years are school-level collections that are **not yet watched** |
| COMMUNICATION | announcements, conversations | `moduleWatch_*` | T2 | **Done** | message text is never recorded |
| COMMUNICATION | notification acknowledged | `school_notifications.js` | | **Not yet in the central trail** | acknowledgement is stored on the notification itself |
| COMMUNICATION | push / e-mail / WhatsApp delivery | `delivery_log.js` | | **Not yet in the central trail** | has its own delivery log |
| ADMISSION | enquiries, applications | `moduleWatch_*` (written by callables, observed as T2) | T2 | **Done** | documents, fees, conversions are not watched yet; status history lives in the admission history collections |
| DATA_CONFIG | school profile, regional, branding, settings, imports, exports of business data | | | **Not yet** | branding/regional callables do not write the central trail yet |
| READ | profile / contact / fee viewed | direct Firestore reads | | **Not capturable** | only exports and audit-log access (above) are observable |

## What the trail can answer
Who changed what, in which school, when, and how reliable that statement is; denied and failed attempts that the server can see; every use of the audit log itself.
It cannot prove what a client says about itself (T4), and it does not see reads.

## Known gaps (kept visible on purpose)
1. App does not send T4 reports yet. 2. Academic setup (classes, sections, subjects, years, holidays), admission documents/fees/conversions, branding/regional/settings changes, notification acknowledgement and delivery are not in the central trail yet.
3. A client write can in principle skip the trigger only if the function is down: the trigger retries until it succeeds, but nothing alerts on a stuck retry (Cloud Monitoring alert not created).
