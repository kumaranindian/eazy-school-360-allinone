# Project Architecture

EazySchool 360, by **Avail404**, is a multi-tenant School Management SaaS
platform targeting Web, Android, and iOS from a single Flutter codebase.
This document covers the platform through **Milestone 5 (attendance
management)**, built on top of Milestone 4's staff/teacher management,
Milestone 3's student/parent management,
Milestone 2's academic configuration, Milestone 1's multi-tenant core, and
Milestone 0's app shell. No business feature beyond master data (fees,
leave, homework, announcements, payroll, timetable, exams, fees)
exists yet; that is intentional and tracked under "Known limitations"
below. For the
tenant/role/permission/Firestore-rules design, see `MULTI_TENANT_GUIDE.md`;
for School Profile/Branch/Academic Year/Class/Section/Subject/Working
Days/Holiday Calendar, see `docs/milestone-2-school-setup.md`; for
Student/Parent/academic enrollment/transfer/withdrawal, see
`docs/milestone-3-student-parent-management.md`; for Staff/Teacher/
Department/Designation/teacher assignments, see
`docs/milestone-4-staff-teacher-management.md`; for student/staff
attendance, see `docs/milestone-5-attendance-management.md` — this document stays at
the "where things live and why" level.

## Repository context

This is a brand-new Flutter project — nothing was reused from any prior
EazySchool implementation. The project lives in its own git repository
(the `eazy-school-360/` directory name is just the on-disk folder — it is
unrelated to the application identifiers below), independent from sibling
projects that happen to share a parent directory on disk.

## Application identity

Four distinct identifiers are involved, and they are **not** the same
thing — see `PACKAGE_MIGRATION_REPORT.md` for the migration that set these:

| Identifier | Value | Where it lives |
|---|---|---|
| Dart/pub package name | `eazy_school_360` | `pubspec.yaml` `name:`; what `package:eazy_school_360/...` imports resolve against. Unrelated to the platform application identifier below — Dart has no Java-style reverse-domain package requirement. |
| Android `namespace` / `applicationId` | `com.avail404.eazyschool.eazyschool360` | `android/app/build.gradle.kts` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.avail404.eazyschool.eazyschool360` (`.RunnerTests` for the test target) | `ios/Runner.xcodeproj/project.pbxproj`, all of Debug/Release/Profile |
| User-facing app name | `EazySchool 360` | Android manifest `android:label`, iOS `CFBundleDisplayName`, web `manifest.json`/`index.html`, in-app `AppBar`/login title |

Changing one of these does not change the others — e.g. renaming the Dart
package would not touch the Android `applicationId`, and vice versa.

## Tech stack

| Concern | Choice | Why |
|---|---|---|
| Language/framework | Flutter 3.32 / Dart 3.8 (stable) | Single codebase for Web, Android, iOS |
| State management | Riverpod (`flutter_riverpod`, no code generation) | Compile-safe DI, testable without a widget tree, no build_runner step to maintain for this milestone |
| Navigation | `go_router` (`StatefulShellRoute.indexedStack`) | Declarative routing, deep-linking/browser back-forward on Web, and a navigation shell that preserves each branch's state |
| Backend | Firebase (Auth, Firestore, Storage) | Matches the brief; Cloud Functions deliberately **not** added — tenant isolation is enforced via Firestore rules using a lookup-table pattern instead of custom claims, which needs no server-side writer; see `MULTI_TENANT_GUIDE.md` → "Security rules" |
| Google Sign-In | `google_sign_in` (mobile) + Firebase `signInWithPopup` (Web) | Added in Milestone 1 specifically for the brief's Google Sign-In requirement — not used anywhere else, so not added speculatively |
| Data classes | Dart 3 `sealed class` / records | Dart 3.8 supports these natively — no need for `freezed`/`equatable` just to get a union type |
| Rules testing | Node (`firestore-tests/`), `@firebase/rules-unit-testing`, Firestore emulator | The only way to actually *prove* tenant isolation without a deployed project — see `MULTI_TENANT_GUIDE.md` → "Testing the rules". Isolated from the Flutter app's own dependency tree (separate `package.json`), since it's rules-only tooling, not app code |

No dependency was added "because it's common" — each one is used by code that
ships in this milestone. See `pubspec.yaml` for the full list.

## Folder structure

```
lib/
  core/            # App-wide infrastructure, no business logic
    config/        # Environment selection, Firebase options per environment
    constants/     # Route paths, Firestore field names, misc literals
    errors/        # AppFailure union + exception → failure mapping
    extensions/    # BuildContext convenience helpers
    logging/       # AppLogger
    permissions/   # UserRole, Permission, RolePermissions — see MULTI_TENANT_GUIDE.md
    routing/       # GoRouter config, the authenticated-area shell
    tenant/        # TenantContext + its provider — see below
    theme/         # Design tokens + ThemeData factory
    utils/         # Responsive breakpoint helpers
    validators/    # Reusable form-field validators

  features/
    authentication/
      data/            # FirebaseAuthRepository (email/password, Google, password reset)
      domain/          # AppUser, AuthRepository interface
      presentation/
        pages/         # LoginPage, ForgotPasswordPage, SplashPage, AccountInactivePage
        widgets/       # LoginForm, ForgotPasswordForm
        providers/     # Riverpod providers/controllers
    dashboard/         # Post-login landing page (presentation only)
    school_setup/
      data/            # FirebaseSchoolRepository (profile edit, logo upload, branches, school creation)
      domain/          # School, Branch, their status enums, SchoolRepository interface
      presentation/
        pages/         # SchoolSetupPage (view/edit), CreateSchoolPage (onboarding), BranchesPage
        widgets/       # CreateSchoolForm, SchoolProfileForm, SchoolLogoPicker, BranchFormDialog
        providers/     # school_providers.dart, create_school_providers.dart, school_profile_providers.dart
    academic_setup/    # Milestone 2 — see docs/milestone-2-school-setup.md
      domain/          # AcademicYear, SchoolClass, Section, Subject, ClassSubjectLink, Holiday, WorkingDays, AcademicSettings, SetupStatus
      data/            # FirebaseAcademicStructureRepository, FirebaseCalendarRepository, FirebaseAcademicSettingsRepository
      presentation/
        pages/         # SettingsOverviewPage + one page per Academic Year/Class/Section/Subject/Working Days/Holidays
        widgets/       # one form dialog per entity, AcademicYearSelector, HolidayCalendarView, ClassSubjectsDialog
        providers/     # one providers file per repository, + setup_status_provider.dart (composition)
    users/
      data/            # FirebaseUserRepository
      domain/          # UserProfile (+ linkedParentId, Milestone 3), UserStatus, UserRepository interface
      presentation/
        pages/         # UsersPage — still a placeholder; see Known limitations
        providers/     # user_providers.dart
    students/          # Milestone 3 — see docs/milestone-3-student-parent-management.md
      domain/          # Student, StudentAcademicRecord, Parent, ParentStudentLink, Gender, BloodGroup,
                       # StudentStatus, AcademicRecordStatus, RelationshipType, PagedResult<T>,
                       # StudentRepository/ParentRepository interfaces
      data/            # FirebaseStudentRepository, FirebaseParentRepository
      presentation/
        pages/         # StudentsListPage, StudentAdmissionPage, StudentProfilePage,
                       # ParentsListPage, ParentProfilePage
        widgets/       # PersonPhotoPicker, ParentFormDialog, LinkParentDialog,
                       # StudentTransferDialog, StudentStatusDialog, StudentPlacementLabel
        providers/     # student_providers.dart, parent_providers.dart, student_keys.dart

    staff/             # Milestone 4 — see docs/milestone-4-staff-teacher-management.md
      domain/          # Staff, StaffStatus, EmploymentType, Department, Designation, TeacherAssignment,
                       # StaffDocument, TeacherAssignmentRules (pure validation), repository interfaces
      data/            # FirebaseStaffRepository, FirebaseStaffSetupRepository, FirebaseTeacherAssignmentRepository
      presentation/
        pages/         # StaffListPage, StaffFormPage, StaffProfilePage (also the teacher profile),
                       # MyStaffProfilePage, TeachersListPage, StaffConfigPage (departments/designations)
        widgets/       # StaffBranchScope, StaffStatusDialog, LinkUserDialog, TeacherAssignmentDialog,
                       # TeachingTab, StaffDocumentsTab, StaffConfigFormDialog, FormGrid, ...
        providers/     # staff_providers.dart, academic_names_provider.dart, staff_keys.dart

    exams/             # Milestone 10 — see docs/milestone-10-examinations-results-report-cards.md
    notifications/     # Milestone 11 — centre, preferences, bell (docs/milestone-11-notifications-parent-teacher-communication.md)
    communication/     # Milestone 11 — parent–teacher conversations
      domain/          # Examination/Subject, GradingScheme, MarksEntry/Sheet, ResultCalculator (pure), ExamRules, ResultSummary
      data/            # Firebase{GradingScheme,Exam,Marks,Result}Repository, ExamWrites (the documents written)
      presentation/    # list, form, detail, schemes, marks entry, review, results, student result, performance, history, family
    homework/          # Milestone 9 — see docs/milestone-9-homework-assignments-announcements.md
      domain/          # Homework, HomeworkSubmission/Revision, HomeworkRules (pure), FilePolicy, repository interfaces
      data/            # Firebase{Homework,Submission}Repository, FirebaseHomeworkFileStore, HomeworkWrites (documents written)
      presentation/    # list, form + preview, detail, review, grading, family list/detail, providers, FamilyScope
    announcements/     # Milestone 9 — audiences, AnnouncementVisibility (pure), AnnouncementWrites, list/form/detail pages
    timetable/         # Milestone 8 — see docs/milestone-8-timetable-substitution.md
      domain/          # PeriodSet/PeriodSlot, Timetable/TimetableEntry, TimetableValidator, TimetableResolver,
                       # TimetablePublication, Substitution + SubstitutionPlanner/Health, TimetableCopier (pure)
      data/            # Firebase{PeriodSet,Timetable,Substitution}Repository, TimetableWrites (the documents written)
      presentation/    # hub, bell schedules, editor, class/teacher/personal views, substitutions, conflicts, history
    leave/             # Milestone 7 — see docs/milestone-7-leave-management.md
      domain/          # LeaveType, LeaveApplication/CalendarEntry/History, LeaveUnits (half-day ints),
                       # LeaveDayCalculator, LeaveWorkflow, LeaveBalance/LeaveBalanceMath, LeaveSubmissionPlanner (pure)
      data/            # Firebase{LeaveApplication,LeaveBalance,...}Repository, LeaveWrites (the documents written)
      presentation/    # hub, queue, detail, apply form, my leave, types, balances, calendar, reports, notices
    fees/              # Milestone 6 — see docs/milestone-6-fees-management.md
      domain/          # Money (integer minor units), FeeStructure, StudentFeeAssignment, Invoice/InvoiceMath,
                       # Payment/Receipt/PaymentReversal, PaymentRules, Assignment/InvoicePlanner (pure), summaries
      data/            # Firebase{FeeConfig,Invoice,Payment,FeeReport}Repository (transactions, aggregate queries)
      presentation/    # hub, structures, assignment, invoices, generation, payments, receipts, reports, parent views
    attendance/        # Milestone 5 — see docs/milestone-5-attendance-management.md
      domain/          # AttendanceStatus, StudentAttendance, StaffAttendance, AttendanceDay (register),
                       # AttendanceSheet + AttendanceSavePlanner (editing/concurrency rules, pure),
                       # AttendanceCalendar, EnrollmentEligibility, StaffEligibility, AttendanceTally,
                       # AttendanceReports/AttendanceCsv; repository interfaces
      data/            # FirebaseStudentAttendanceRepository, FirebaseStaffAttendanceRepository,
                       # AttendanceRegisterTransaction (the one shared save algorithm)
      presentation/
        pages/         # AttendanceHubPage (dashboard), StudentAttendancePage, StaffAttendancePage,
                       # AttendanceReportsPage
        widgets/       # RegisterEditor (save/finalize/conflict flow), AttendanceSheetRows,
                       # AttendanceStatusButtons, AttendanceSummaryBar, calendar_support
        providers/     # attendance_providers.dart

  shared/            # Cross-feature, non-infrastructure widgets
    dialogs/         # Responsive dialog wrapper
    paging/          # PagedListController — reusable cursor-pagination state
    error/            # ErrorView, EmptyView
    layouts/          # AdaptiveScaffold (responsive nav shell)
    loading/          # LoadingIndicator, AsyncValueWidget

  app/
    app.dart         # MaterialApp.router + theme + router wiring
    bootstrap.dart   # Shared startup path used by every main_*.dart

  main.dart          # Default entry point (= main_dev.dart)
  main_dev.dart / main_test.dart / main_uat.dart / main_prod.dart
```

Each feature owns its own `data/domain/presentation` split. `users` has a
real domain/data layer now (`UserProfile`, `FirebaseUserRepository`) but
its presentation layer is still a placeholder page — listing/inviting
staff is UI work for a later milestone; see Known limitations.

### `core/tenant/` — the one exception to "core has no business logic"

`TenantContext` (user + school + branch + derived permissions) composes
domain types from the `users` and `school_setup` features — a deliberate,
narrow exception to "core is infrastructure only," because tenant context
is genuinely cross-cutting (routing guards, the nav shell, every future
business feature will read it). It is not a place for feature-specific
logic to leak into; it only assembles what `authentication`, `users`, and
`school_setup` already expose. See `MULTI_TENANT_GUIDE.md` for the full
design.

### Why feature-first, not `lib/models/`, `lib/services/`, `lib/screens/`

A layer-first split forces every change to a single feature to touch three
or more top-level folders. Feature-first keeps everything one feature needs
in one place, and `core/`/`shared/` stay small and genuinely
cross-cutting — they are not a dumping ground for "things more than one
feature happens to use yet."

### Layering inside a feature

```
presentation (pages/widgets) → providers/controllers → domain (repository interface, models) → data (repository implementation → Firebase)
```

`authentication` is the fully-wired example: `LoginPage`/`LoginForm` never
call Firebase directly — they read `AuthRepository` through a Riverpod
provider, and the concrete `FirebaseAuthRepository` is the only place that
imports `firebase_auth`. This is also what makes `authRepositoryProvider`
overridable with a fake in tests (see `test/widget/app_smoke_test.dart`)
without touching real Firebase.

## Responsive & navigation foundation

- `core/utils/responsive.dart` defines breakpoints (mobile < 600, tablet
  600–1024, desktop > 1024) and a `ResponsiveBuilder` that re-resolves on
  every relayout via `LayoutBuilder` — not a cached `MediaQuery` read.
- `shared/layouts/adaptive_scaffold.dart` is the one navigation shell used
  by every authenticated route: bottom nav on mobile, a compact
  `NavigationRail` on tablet, an extended rail (sidebar-style) on desktop.
  A new top-level destination is one entry in the destinations list, not a
  new screen per platform.
- `shared/dialogs/app_dialog.dart` adapts dialog width the same way, and
  scrolls instead of overflowing when content exceeds viewport height
  (keyboard-open safe).

## Theming

`core/theme/` centralizes colors, typography, spacing, and radius as design
tokens, assembled into light/dark `ThemeData` in `app_theme.dart`. Buttons,
inputs, cards, dialogs, and data tables are styled once there — screens
should never construct ad hoc `BoxDecoration`/`TextStyle` literals for
things this already covers.

## Error handling & async states

- `core/errors/app_failure.dart` defines the small, closed set of failures
  the UI is allowed to branch on (`NetworkFailure`, `AuthFailure`,
  `PermissionFailure`, `NotFoundFailure`, `ValidationFailure`,
  `UnknownFailure`).
- `core/errors/error_mapper.dart` maps `FirebaseAuthException`/
  `FirebaseException`/`SocketException` to one of those — this is the only
  place that needs to know what a raw Firebase error code means.
- `shared/loading/async_value_widget.dart` renders any Riverpod
  `AsyncValue` as loading/error/data consistently, so "the spinner never
  spins forever" is structural (handled by `AsyncValue.guard` +
  `AsyncNotifier`) rather than something each screen has to remember.

## Environment strategy

See `DEVELOPMENT_GUIDE.md` for day-to-day commands. In short: four
environments (`dev`, `test`, `uat`, `prod`), selected by which
`lib/main_<env>.dart` entry point is run, each resolving its own
`EnvConfig` (app name + `FirebaseOptions`) — nothing environment-specific is
hardcoded into shared code.

## Known limitations (explicitly deferred, not oversights)

- **Student + Parent management** (Milestone 3) and **Staff + Teacher
  management** (Milestone 4) are implemented for master data. Fee,
  Attendance, Leave, Homework, Payroll, Timetable, Announcement and Report
  modules remain out of scope — explicitly excluded by every milestone's
  brief so far. See `docs/milestone-3-student-parent-management.md` and
  `docs/milestone-4-staff-teacher-management.md`.
- **`users` has no management UI yet.** The domain/data/provider layers
  are real (`UserProfile`, `FirebaseUserRepository`, Firestore rules
  enforcing who can create/update whom), but there's no screen yet to list
  staff, invite a new user, or change someone's role — `UsersPage` is
  still a placeholder. The backend foundation (rules permit a `SCHOOL_ADMIN`
  to provision `BRANCH_ADMIN`/`TEACHER`/`FINANCE`/`PARENT` users — see
  `MULTI_TENANT_GUIDE.md`) is ready for that UI to be built against.
- **School Profile and Branch management are now fully editable** (Milestone
  2) — this item from Milestone 1 is resolved; `SchoolSetupPage` has
  view/edit/save/cancel, logo upload, and `BranchesPage` has full branch
  CRUD. See `docs/milestone-2-school-setup.md`.
- **Suspended/inactive schools are not enforced.** `SchoolStatus` exists
  and a `SCHOOL_ADMIN` can no longer change it, but neither the client nor
  the rules block a school's users when its status is `SUSPENDED`/`INACTIVE`
  — the semantics of each status are a product decision still to be made.
- **Academic structure validation (duplicate names, overlapping active
  years) has no automated repository-level test**, only model-serialization
  and Firestore-rules coverage — see `docs/milestone-2-school-setup.md` →
  "Known issues" for why (would need a new `fake_cloud_firestore`-style
  dependency not yet justified).
- **Class-subject association has no read-only view for `viewAcademicSetup`
  holders** (teacher/finance) — only `manageAcademicSetup` admins can open
  it from the Classes page.
- **No way to create a Firebase Auth account for another person.** Rules
  allow admins to create `/users` profiles for subordinates, but creating
  the underlying sign-in account needs a trusted server (Admin SDK / Cloud
  Function) or an invitation flow. Self-signup is the only working user
  creation path today.
- **No Cloud Functions, no custom claims.** Tenant isolation is enforced
  via a Firestore-rules lookup-table pattern instead — see
  `MULTI_TENANT_GUIDE.md` → "Security rules" for the full reasoning and
  when custom claims would become worth the added infrastructure (lower
  rule read-costs at higher scale).
- **No real Firebase project.** Every environment's `FirebaseOptions` is a
  gitignored local file generated via `flutterfire configure` — see
  `FIRESTORE_ARCHITECTURE.md` and `SECURITY_ARCHITECTURE.md`. Firebase init
  fails gracefully (logged, not a crash) until real projects exist. This
  also means Google Sign-In, while fully implemented in code, cannot
  actually complete a sign-in until a real project + OAuth client exist —
  see `SECURITY_ARCHITECTURE.md` → "Google Sign-In".
- **No custom in-app password-reset screen.** "Forgot password" sends
  Firebase's standard reset email, which lands on Firebase's own hosted
  action-handler page — not reimplemented in-app for this milestone.
- **Branch transfer for a student is not supported.** A student's
  document lives under one specific branch path; moving them to another
  branch would mean creating a new document under a different path and
  migrating every subcollection — genuinely complex, and explicitly
  allowed to be deferred rather than faked (brief §19). `StudentTransferDialog`
  only offers year/class/section within the student's current branch.
- **No Dart-level repository tests for Student/Parent duplicate/
  referential-integrity validation** (admission-number uniqueness,
  section-belongs-to-class) — same reasoning and same gap as the
  Milestone 2 academic-structure repository: covered by Firestore-rules
  tenant/role tests and model-serialization tests, not a live-Firestore
  integration test.
- **No Academic Settings UI page yet** (model/repository/provider exist
  from Milestone 2, but no `/settings/*` screen edits them) — unrelated to
  Milestone 3, carried over from Milestone 2's own known issues.
- **Parent portal access has no self-service flow.** `Parent.linkedUserId`/
  `UserProfile.linkedParentId` and the Firestore rules that make a linked
  parent's read access work are all in place and tested, but there is no
  UI yet for an admin to create the actual Firebase Auth account for a
  parent and link it in one step — see
  `docs/milestone-3-student-parent-management.md` → "Parent portal access
  foundation". This is explicitly the foundation the brief asked for, not
  the Parent Portal itself (a future milestone).

- **Staff + Teacher known limitations** (details and priorities in
  `docs/milestone-4-staff-teacher-management.md` → "Known issues"):
  repository classes have no live-Firestore automated test (covered by the
  emulator rules tests plus pure-logic unit tests); `Staff.isTeacher` cannot
  be switched off while assignments are active, but only the client
  enforces it; linking an account to a staff record needs the user's ID
  because there is still no user-listing UI; a teacher's student read is
  still the branch-wide Milestone 3 grant.
- **Teachers' student access is not yet narrowed to their sections.** The
  teacher-assignment model now exists, so a future milestone can restrict
  `viewStudentData` for the `TEACHER` role to the sections they are
  assigned to; Milestone 4 deliberately did not change Milestone 3's rules.

- **Attendance known limitations** (details in
  `docs/milestone-5-attendance-management.md` → "Known limitations"): the
  enrollment check, the holiday/working-day check and the register counts are
  enforced by the client, not Firestore rules (rules cannot afford a read per
  student or look up calendar dates); the attendance repositories have no
  live-Firestore test; only a section's class teacher can mark it; no re-open
  UI, offline sync, or check-in/out times; "today" is the device date.
- **`HolidayType.specialWorkingDay`** was added to the Milestone 2 calendar
  so a Saturday can be a school day; it is stored like any holiday entry.

## Recommended next milestone

**Milestone 6 — Fees Management, Invoices, Payments and Receipts.** It can
reuse this foundation: students and their year-by-year `academicRecords`
(who owes what, in which class), the audit-field and status-lifecycle
patterns, deterministic-id uniqueness and revision-checked transactions
(invoice numbers, receipts and payments must be idempotent, exactly like
attendance saves), and the permission/route guard pattern for a `FINANCE`
role that today can only view students and staff.
