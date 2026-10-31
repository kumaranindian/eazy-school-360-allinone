# In-app User Manual – feature audit (pre-implementation)

Status: audit only. No manual code has been written. Findings come from
`lib/core/routing/app_routes.dart`, `app_shell.dart`,
`lib/core/permissions/*`, `firestore.rules` and the feature folders.
Items marked **verify** were only grepped, not exercised in the running app.

## 1. Roles (real ones)

| Brief says | Application has | Notes |
|---|---|---|
| Admin | `SCHOOL_ADMIN`, `BRANCH_ADMIN`, `PLATFORM_ADMIN` | School/Platform admin also manage school profile, branches, authentication. |
| Accountant / Finance | `FINANCE` | View students/parents/staff/attendance; assign fees, issue invoices, collect payments, fee reports. Cannot create fee structures, grant concessions, void invoices or reverse payments (those are admin-only). |
| Office Staff | **no such role** | Closest is `BRANCH_ADMIN` (student data, staff, attendance, fees). Manual must say "Branch admin", not invent a role. |
| Teacher | `TEACHER` | Mark attendance, homework (manage + review submissions), enter marks, announcements, own timetable. No parent list, no student editing. |
| Parent | `PARENT` | My Fees, My Attendance, My Timetable, My Homework, My Results, announcements, messages, notifications. |

Role gating lives in `RolePermissions.grants`; routes are gated by
`AppRoutes.requiredPermissions`. The manual should filter by **permission**,
not by role name, so it never disagrees with the app.

## 2. Navigation (app_shell.dart)

Dashboard, School, Settings, Students, Parents, Staff, Attendance, Fees,
My Fees, Leave, My Leave, Timetable, My Timetable, Homework, My Homework,
Announcements, Exams, My Attendance, My Results, Notifications, Messages,
My Profile, Users. **No Help item exists today.** There is no existing help
or manual feature to extend or duplicate.

## 3. Workflow → real screens

| Workflow | Real routes | Availability |
|---|---|---|
| A School setup | `/school`, `/settings` (`branches`, `academic-years`, `classes`, `sections`, `subjects`, `working-days`, `holidays`, `regional`, `authentication`) | Implemented. Class–subject mapping exists (`classSubjects` collection). |
| B Admission + parent login | `/students/new` (wizard: Basic → Parent/guardian → Placement → Review), `/parents`, "Give login access" (`provisionLogins` callable), `/users` | Implemented. Parent **record** ≠ parent **login**; logins are separate, server-side, with a password-setup option per batch. Bulk import never creates logins. Admission number is auto-generated (`ADM-0001`). |
| C Fee structure | `/fees/structures` | Implemented. Frequencies: one-time, monthly, quarterly, half-yearly, annual, custom (no "term-wise" as such). **Verify**: late-fee rules. Installments: **not found**. |
| D Fee assignment | `/fees/assign` | Implemented. Concessions via `grantConcessions` (admin only) – **verify** where in UI. |
| E Invoices | `/fees/invoices`, `/fees/invoices/generate`, `/fees/invoices/:id` | Implemented; void = `voidInvoices` (admin). Invoice numbers server-reserved (`invoiceNumbers`). Parent view `/my-fees`. |
| F Payments | `/fees/payments`, `/fees/receipts/:id`, `/my-fees/receipts/:id` | Implemented for staff-recorded payments; reversal = `reversePayments` (admin). **Online payment does NOT exist** ("Pay online – coming soon", `PayOnlineComingSoon`). |
| G Timetable | `/timetable`, `/timetable/periods`, `/timetable/editor/:id`, `/timetable/conflicts`, `/timetable/substitutions`, `/my-timetable` | Implemented, with publish (`publishTimetable`) and conflict view. |
| H Homework | `/homework`, `/homework/new`, `/homework/review/:id`, `/my-homework` | Implemented, including attachments and submission review (`reviewSubmissions`). |
| I Exams | `/exams`, `/exams/new`, `/exams/schemes`, `/exams/marks/…`, `/exams/review/:id`, `/exams/results/:id`, `/my-results` | Implemented with grading schemes, marks review/approval, publishing, ranking and report cards (**verify** report-card export). |
| J Attendance | `/attendance`, `/attendance/students`, `/attendance/staff`, `/attendance/reports`, `/my-attendance` | Student and staff attendance implemented. |
| K Staff | `/staff`, `/staff/new`, `/staff/departments`, `/staff/designations`, `/teachers` | Implemented; logins via the same provisioning dialog. |
| L Announcements | `/announcements`, `/announcements/new`, `/notifications`, `/messages` | Implemented with attachments. **Web push not supported**; Android push needs Cloud Functions (not deployable on prod yet). |
| M Reports | `/fees/reports`, `/attendance/reports`, `/leave/reports`, `/exams/performance` | Fee, attendance, leave, exam-performance reports exist. A student report, staff report, invoice report and receipt report **were not found** as separate screens – must not be documented as if they exist. |
| Extra (not in brief) | Leave management (`/leave*`, `/my-leave*`), Account deletion, multi-branch switching, regional settings | Real features a complete manual should cover. |

## 4. Firestore and rules constraints for editable manual content

- Tenant data lives under `schools/{s}/branches/{b}/…`; every doc needs
  `schoolId`/`branchId` plus audit fields.
- Any new collection needs, in the same change: a block in `firestore.rules`,
  allowed and denied cases in `firestore-tests/`, and an entry in the account
  deletion matrix (`functions/deletion_coverage.test.js` fails otherwise).
- `firestore.rules` is already near the release limit (see memory notes on the
  1000-expression and source-op-count limits), so four new collections is a
  real cost, not a free addition.
- A global (non-tenant) manual would be a new platform-level collection with
  no existing precedent in the rules.

## 5. Recommendation (needs your decision)

1. **Ship the manual content bundled with the app** (typed Dart/JSON, versioned
   in git, filtered by permission). It cannot drift from the routes, works
   offline, needs no rules/tests/deletion-matrix changes, and its deep links use
   `AppRoutes` constants instead of hardcoded paths.
2. **Store only per-user progress in Firestore**: one small
   `users/{uid}/manualProgress/{guideId}` document, owner read/write only.
   One rules block, with a deletion-matrix entry.
3. **Defer admin-editable content** (the brief's `user_manual_*` collections)
   to a later phase. Content updates then ship with an app release.
4. **Phase the content** (13 workflows × 4 roles is large):
   - Phase 1: framework (Help entry, guide list, stepper UI with progress,
     search, role filter, contextual help button) + Getting Started + Workflows
     A, B, C, D, E, F.
   - Phase 2: G–M, troubleshooting, FAQ, parent guide.
5. **Screenshots**: none exist in the repo. Plan for text and deep links first;
   add an optional `screenshotAsset` field so images can be added later.
6. Guide steps only navigate (`context.go(AppRoutes…)`); marking a step done
   writes progress only and never triggers a fee, invoice or admin action.

## 6. Questions before building

1. Bundled content + Firestore progress only (recommended), or full
   Firestore-managed content now?
2. OK to say "Branch admin" where the brief says "Office Staff", since no such
   role exists?
3. Phase 1 scope as above, or a different cut?
4. Should the manual cover features outside the brief that do exist (Leave,
   Account deletion, multi-branch)?
