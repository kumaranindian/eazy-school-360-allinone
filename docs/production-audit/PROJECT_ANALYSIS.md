# Project analysis

Audited commit: `develop` @ `f36c35f` (2026-10-17). Method: repository inspection, safe local test runs, and four read-only sub-audits whose claims are tagged in BUG_REGISTER.md. Cloud-console state (Firebase projects, Play/App Store, Google Cloud) was **not** inspected — see PRODUCTION_CONFIGURATION_AUDIT.md.

## Stack (verified from manifests)
| Layer | What is actually present |
|---|---|
| Client | Flutter 3.32.8 (CI pin) / Dart ≥3.8.1; 480 Dart files in `lib/`; Riverpod 3.3 (no codegen), go_router 17, Firebase Auth/Firestore/Storage/Messaging/Functions/App Check/Crashlytics, `pdf` + `printing` for receipts/report cards |
| Targets | Web (primary, Firebase Hosting), Android, iOS. Package/bundle id `com.avail404.eazyschool.eazyschool360` for dev **and** prod (no flavors) |
| Backend | **Only Firebase.** No Spring Boot, Dart Shelf/Frog or other server exists. Cloud Functions v2, Node 22, region `asia-south1`, `maxInstances: 10`, 26 exported functions (`functions/index.js`): push fan-out + event notices + `feeDueReminders` schedule, device registration, OTP (Meta WhatsApp), login-access management, provisioning, role-index maintenance (`teacherAccess`, `parentAccess`, `exam_scope`), `setBranchAccess` |
| Data | Firestore, strictly `schools/{schoolId}/branches/{branchId}/…`; flat `/users/{uid}` lookup table; 84 `match` blocks, 91 composite indexes, 3 field overrides (TTL, collection-group) |
| Authorization | Firestore/Storage rules via lookup table on `/users` (no custom claims). Roles: PLATFORM_ADMIN, SCHOOL_ADMIN, BRANCH_ADMIN, FINANCE, TEACHER, PARENT; plus per-branch roles (`users.branchRoles`, server-written) |
| Tests | 1,432 Dart tests in 99 files, 132 Node tests for functions (15 files), 437 rules-emulator tests (34 files, incl. Dart-generated contract fixtures) |
| CI | `.github/workflows/ci.yml`: `flutter` (format, analyze, test, OSV scan, web build), `rules` (fixtures, `npm audit --audit-level=critical`, emulators), `functions` (npm ci + test). No deploy job. |

## Entry points & environments
`lib/main_dev.dart`, `main_prod.dart` (real Firebase projects `eazy-school-360-dev/-prod`); `main_test.dart` / `main_uat.dart` hold placeholders and refuse to start; `main.dart` requires `--dart-define=APP_ENV` and has no default. `FirebaseConfigValidator` rejects cross-environment options. There is **no staging environment** with a real project.

## Architecture
Feature-first `lib/features/<f>/{domain,data,presentation}`; pure domain rule classes (`PaymentRules`, `InvoiceMath`, `AttendanceSavePlanner`, `ResultCalculator`, …) and "write-plan" classes (`*Writes`) whose output is exported as JSON and replayed against the real rules (exam, homework, leave, timetable, communication, branch transfer). Attendance has **no** write-plan/contract fixture (gap). Widgets reach Firebase only through repository providers.

## Data flow
UI → Riverpod `AsyncNotifier`/providers → repository → Firestore (transactions/batches) → rules enforce tenant/role/field/state → Cloud Function triggers on `notifications`, `broadcastNotices`, role/index documents → FCM. Roles/permissions in `lib/core/permissions` only drive UI visibility; the rules are the boundary (verified by the 437-test suite).

## Integrations
Firebase (Auth: email/password, Google, phone OTP via custom token), Meta WhatsApp Cloud API (secrets in Secret Manager), FCM (web VAPID via `FCM_VAPID_KEY` define, APNs, Android channel `eazyschool_general`). No payment gateway: fees are recorded by staff (cash/UPI/etc. entries), **no online payment** exists.

## Observations on structure
* Dead code / TODOs: none found (`grep` TODO/FIXME/HACK = 0 in `lib/`, `functions/`, rules).
* Conflicting sources of truth: `PROJECT_ARCHITECTURE.md` still says Cloud Functions were not added (stale; CLAUDE.md is correct). Current-placement cache on `students` vs `academicRecords` is documented and maintained by the repository (see ACAD-7 for the race).
* Derived indexes (`parentAccess`, `teacherAccess`) are server-maintained; their absence fails closed.
* Two date conventions coexist (UTC-midnight holidays and civil-date keys vs local-midnight academic years) — root of ACAD-1.
* `firestore.rules` is one 223,727-byte file at the edge of the release limit (SEC-1).
