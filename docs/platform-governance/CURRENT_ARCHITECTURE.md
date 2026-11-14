# Current architecture (verified in the repository, 2026-11-14)

## Stack and environments
Flutter 3.32 (Web, Android, iOS), Riverpod, GoRouter; Firebase Auth, Firestore, Storage, Cloud Functions (Node 22, `asia-south1`),
Hosting. Two real projects: `eazy-school-360-dev`, `eazy-school-360-prod`. Prod has Identity Platform with authenticator-app MFA enabled
(2026-11-14); dev does not yet.

## Tenancy
`schools/{schoolId}/branches/{branchId}/...`; every tenant document carries `schoolId` (and `branchId`) and audit fields
(`createdBy`, `updatedBy`, `createdAt`, `updatedAt`). The rules enforce that those actor fields equal `request.auth.uid`
(`validCreateAudit`, `validUpdateAudit`), so a document's `updatedBy` is trustworthy evidence of the actor.

## Identity and roles
`/users/{uid}` is the lookup table (no custom claims): `role` (PLATFORM_ADMIN, SCHOOL_ADMIN, BRANCH_ADMIN, TEACHER, FINANCE, PARENT),
`schoolId`, `branchId`, `status`, server-written `login` policy, `branchRoles`, and mirrors written by Cloud Functions (`parentAccess`,
`teacherAccess`, and since Phase 3 of platform admin `schoolAccess: 'SUSPENDED'`). `TenantContext` is built once from this profile.
Platform admins have `schoolId: null`, a `platformRole` (OWNER/SUPPORT/COMPLIANCE/VIEWER) and must sign in with a second factor.

## How data is written (this decides what can be audited and enforced)
| Module | Write path |
|---|---|
| Admission (enquiries, applications, documents, fees, conversion), public portal | **Callables** (`admission*.js`) |
| Provisioning of logins, school admins, auth settings, branding, fee-reminder settings | **Callables** |
| Account deletion, platform admin, support access, school lifecycle, billing, notices | **Callables** |
| Students, parents, staff, classes/sections/subjects/years/holidays, attendance, leave, fees (structures, assignments, invoices, payments), exams/marks/results, homework, announcements, timetable, messages | **Client writes direct to Firestore**, authorised by security rules |
| Push/notification fan-out, parent/teacher access indexes, currency lock, exam scope stamp | **Firestore triggers** |

## Security rules constraints
`firestore.rules` (about 4,200 lines) uses helper functions over the caller profile. Two hard limits apply: the **compiled-size release
limit of 256,000 bytes** (a release above it fails with PATCH 400 then POST 409; the real message appears only with `--debug`) and an
operation-count limit on source. After the platform work the compiled size is within the limit with a thin margin, and platform data was
moved to callables specifically to make room. Consequence: any design that adds a clause per module or per collection to the rules is not feasible.

## What already exists for this request
- **School status**: `schools.status` is ACTIVE / INACTIVE / SUSPENDED. `setSchoolStatus` (owner-only, reason required) writes it and a function
  mirrors it onto every profile of the school as `schoolAccess`; rules, Storage rules and callables refuse paused users; the app shows a
  "paused" screen. INACTIVE is treated like SUSPENDED. There is no EXPIRED/CLOSED, no lifecycle history collection, and new schools are created ACTIVE.
- **Self-registration** (`createSchoolForCurrentUser`) writes the school as ACTIVE; the rules *require* `status == 'ACTIVE'` on school creation.
- **Per-school module switches**: `schools.features` with two keys (`admission`, `publicAdmission`), enforced in admission callables, the public
  portal and the app (`TenantContext.can`). No feature catalogue, dependencies, history or global defaults.
- **Subscriptions**: none. There are manual billing records (`platformBilling`, owner-only, amounts owed to Avail404), which are not entitlements.
- **Notifications**: `notifications` documents plus FCM push for staff/parent events; platform notices (`platformNotices`, read through
  `listMyNotices`, in-app dismissible banner with session-only dismissal). No persistent acknowledgement or delivery state.
- **Audit**: `platformAuditLog` (platform actions, written by functions, readable by owner/compliance through `listAuditLog`), per-school
  `authAudit` (login-access changes) and `supportAccessLog`. No audit of ordinary business operations.
- **Platform console**: schools directory and overview, support sessions (read-only grants), deletion review, audit viewer, dashboard,
  maintenance mode and minimum app build (see `docs/platform-admin/`).
- **Scheduled jobs**: `platformStatsRollup` (nightly), fee reminders, push redrive, admission follow-ups, deletion sweeps.

## Backward-compatibility facts
- Existing prod schools have `status: 'ACTIVE'` and no subscription or feature documents. Any new rule must treat "absent" as today's behaviour.
- Existing clients write `status: 'ACTIVE'` on school create; changing the default needs a rules change and an app release.
