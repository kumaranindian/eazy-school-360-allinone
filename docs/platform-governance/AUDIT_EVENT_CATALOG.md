# Audit event catalogue

Capture mechanism per event, mapped to what exists. Trust levels: T1 transactional, T2 observed by trigger, T3 system, T4 client-reported.
"Today" = already captured in some form.

| Category | Events | Capture | Today |
|---|---|---|---|
| A Authentication | login success | T3 Identity Platform blocking function `beforeUserSignedIn` (prod has Identity Platform; adds sign-in latency, needs approval) | no |
| | login failed, permission denied, logout, session expiry | T4 client-reported only (Auth rejects before our code) | no |
| | password reset requested/changed, account locked/unlocked, enabled/disabled, role changed, user created/deleted, invitation, authentication provider change | T1 in `provision.js`, `setLoginAccess`, `setBranchAccess`, `createSchoolAdmin`, `resetLoginPassword`, `changeInitialPassword`, account deletion | partial (`authAudit` per school for login-access changes) |
| B School lifecycle | created/updated/activated/deactivated/suspended/reactivated/expired/closed, owner changed, contact/config changed, branch created/updated/disabled/enabled | T1 for lifecycle (new `transitionSchool`); school/branch profile edits are client writes -> T2 | platform actions yes; profile/branch edits no |
| C Subscription | created/activated/renewed/extended/plan/start/expiry changed, grace, expired, cancelled, reactivated, access blocked | T1 (admin) and T3 (scheduler) | no |
| D Feature | enabled/disabled/config, global default, override, dependency failure, access denied | T1; "access denied" from callables (T1) and the trigger (T2) | partial (`SCHOOL_FEATURES_CHANGED`) |
| E Students | created/updated/archived/activated/transferred/class/section changed, admission confirmed | T2 on `students`, `academicRecords`; admission conversion T1 | admission conversion only |
| F Parents | created/updated/enabled/disabled, relationship created/updated/removed | T2 on `parents`, `parentLinks` | no |
| G Staff | created/updated/archived/activated, role/permission change, branch assign/remove | T2 on `staff`; role/branch via callables T1 | role/branch partial |
| H Attendance and leave | marked/updated/finalised/reopened/bulk/corrected; leave created/approved/rejected/cancelled | T2 on attendance registers and `leaveApplications` | no |
| I Fees | structure, invoice, payment, refund, concession, reminder sent, reminder settings | T2 on `feeStructures`, `invoices`, `payments`; reminder settings T1; reminder send T3 | settings only |
| J Academic | classes, sections, subjects, exams, marks, report cards, timetable, homework, assignments, announcements, holidays, years | T2 on the corresponding collections | no |
| K Admission | all enquiry/application/document/fee/conversion events | T1 in `admission*.js` (callables) | partially (status history and activities exist as business records) |
| L Communication | announcement created/published, notification generated/delivered/acknowledged, email/WhatsApp initiated and status | T2/T3; delivery status where the provider reports it (`delivery_log.js`); acknowledgement T1 | delivery log yes |
| M Data and config | settings, regional, theme, logo, academic year, export, import, bulk, archive | T1 for branding/regional callables, T2 for the rest, T1 for exports | branding partial |
| Platform | admin created/role/status, support access, billing, notices, app requirements, offboarding | T1 | **yes** (`platformAuditLog`) |

Reads: only exports, document downloads through callables and audit-log access are auditable. Every other read category in the request is not achievable (D8).
