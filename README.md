# EazySchool 360

A multi-tenant School Management SaaS platform (Web, Android, iOS) by
**Avail404**, built with Flutter, Firebase, Riverpod, and GoRouter.

Application identifier: `com.avail404.eazyschool.eazyschool360` (Android
`applicationId` / iOS bundle id — see `PROJECT_ARCHITECTURE.md` →
"Application identity" for how this relates to the Dart package name).

This repository is through **Milestone 12 (production hardening; see docs/milestone-12-production-readiness.md — not release-ready)**, after Milestone 11 (notifications and parent–teacher communication; push not implemented), building on Milestone 10 (examinations, marks, report cards and academic performance):
the app shell (M0), email/password and Google sign-in with a
School/Branch/User tenant model, a centralized role/permission system and
Firestore security rules that genuinely enforce tenant isolation (M1,
proven against the Firestore emulator — see `firestore-tests/`), school
setup and academic configuration (M2), student and parent management (M3),
staff, teachers, departments, designations and academic-year-aware
teacher assignments (M4 — see
[`docs/milestone-4-staff-teacher-management.md`](docs/milestone-4-staff-teacher-management.md)),
and student and staff attendance with bulk marking, finalization,
corrections, calendar integration and reports (M5 — see
[`docs/milestone-5-attendance-management.md`](docs/milestone-5-attendance-management.md)),
and fees, invoices, payments, receipts and parent fee views, with no payment
gateway (M6 — see [`docs/milestone-6-fees-management.md`](docs/milestone-6-fees-management.md)).
and student and staff leave: configurable leave types, parent and staff
applications, an approval workflow with a history, staff balances and a
ledger, a leave calendar, reports and in-app notices, shown as an annotation
on attendance (M7 — see
[`docs/milestone-7-leave-management.md`](docs/milestone-7-leave-management.md)).
and versioned class/section timetables with bell schedules, conflict
detection, atomic publication, and date-specific teacher substitutions
(M8 — see
[`docs/milestone-8-timetable-substitution.md`](docs/milestone-8-timetable-substitution.md)).
and homework with per-section publication, parent submissions, teacher
review and grading with a full revision history, plus audience-targeted
announcements, in-app notices and validated file attachments
(M9 — see
[`docs/milestone-9-homework-assignments-announcements.md`](docs/milestone-9-homework-assignments-announcements.md)).
and examinations with configurable grading schemes, marks entry and review,
deterministic result calculation, versioned finalised results, publication
and corrections, report cards (PDF) and academic performance summaries
(M10 — see
[`docs/milestone-10-examinations-results-report-cards.md`](docs/milestone-10-examinations-results-report-cards.md)).
No Payroll or chat feature exists yet; that's by design. See [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md) for the
full rationale and "Known limitations."

## Documentation

- [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md) — folder structure,
  architecture decisions, known limitations, recommended next milestone
- [`MULTI_TENANT_GUIDE.md`](MULTI_TENANT_GUIDE.md) — tenant/user/role/
  permission model, authentication flow, Firestore structure and security
  rules, how to add a new role or tenant-aware feature
- [`FIRESTORE_ARCHITECTURE.md`](FIRESTORE_ARCHITECTURE.md) — multi-tenancy
  and data strategy
- [`SECURITY_ARCHITECTURE.md`](SECURITY_ARCHITECTURE.md) — auth vs.
  authorization, the client-is-never-the-boundary principle, custom
  claims vs. lookup rules
- [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) — environment setup,
  running, testing (including the Firestore rules tests), building
- [`PACKAGE_MIGRATION_REPORT.md`](PACKAGE_MIGRATION_REPORT.md) — the
  Avail404 package/application identity migration and what it touched

## Quick start

```
flutter pub get
flutter run -t lib/main_dev.dart --dart-define=APP_ENV=dev -d chrome
```

Dev and prod use separate Firebase projects, selected explicitly by entry
point — see [`docs/firebase-environment-configuration.md`](docs/firebase-environment-configuration.md).

## Tech stack

Flutter · Dart · Firebase (Auth, Firestore, Storage) · Riverpod · GoRouter
