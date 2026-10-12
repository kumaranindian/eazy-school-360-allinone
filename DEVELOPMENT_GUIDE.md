# Development Guide

## Prerequisites

- Flutter 3.32+ (stable channel), Dart 3.8+
- For Android: Android SDK 35, a JDK 17 (`flutter config --jdk-dir` if not
  auto-detected)
- For iOS: Xcode with a Simulator runtime installed, CocoaPods
- `flutterfire` CLI for generating per-environment Firebase config:
  `dart pub global activate flutterfire_cli`
- The Firebase CLI (`npm install -g firebase-tools`) — needed both to
  deploy `firestore.rules`/`storage.rules` and to run the Firestore
  emulator for the rules tests below
- Node 18+ and npm, only for `firestore-tests/` (rules tests) — not a
  dependency of the Flutter app itself

Run `flutter doctor` and resolve anything it flags before continuing.

## Environments

Four environments exist in code — `dev`, `test`, `uat`, `prod` — each with
its own `lib/main_<env>.dart` entry point and options file. **Only `dev` and
`prod` have Firebase projects configured**; `test` and `uat` hold placeholders
and refuse to start (they are never aliased to dev or prod). Nothing
environment-specific is hardcoded in shared code; see
`lib/core/config/env_config.dart`.

### Configuring or changing an environment

See [`docs/firebase-environment-configuration.md`](docs/firebase-environment-configuration.md):
the options live in `lib/core/config/firebase_options/firebase_options_<env>.dart`
(one block per platform, committed — they are public client identifiers), the
owner-supplied native registrations are kept for reference and checked by a
test under `config/firebase/<env>/`, and startup validates the selection and
stops on any mismatch.

## Running locally

```
flutter pub get
flutter run -t lib/main_dev.dart -d chrome      # Web, dev
flutter run -t lib/main_dev.dart -d <device-id>  # Android/iOS, dev
```

The environment is chosen **explicitly**: dedicated entry points
(`main_dev.dart`, `main_prod.dart`) and, optionally, `--dart-define=APP_ENV=dev|prod`
which must agree with the entry point. `lib/main.dart` *requires* the define and
stops with a startup error without it — there is no default environment.
`main_test.dart` / `main_uat.dart` have no Firebase project configured and
refuse to start. Full details, project mapping and verification:
[`docs/firebase-environment-configuration.md`](docs/firebase-environment-configuration.md).

```
flutter run -t lib/main_dev.dart --dart-define=APP_ENV=dev -d chrome
flutter build web --release -t lib/main_prod.dart --dart-define=APP_ENV=prod
flutter build apk --release -t lib/main_prod.dart --dart-define=APP_ENV=prod
```

## Testing

```
flutter analyze   # must be clean before merging
flutter test      # unit + widget tests
```

Milestone 4 widget tests (`test/widget/staff_ui_test.dart`,
`teacher_assignment_dialog_test.dart`) pump the real app/router against
`FakeStaffRepository`, `FakeStaffSetupRepository`,
`FakeAcademicStructureRepository` and `FakeTeacherAssignmentRepository`
(`test/support/staff_fakes.dart`). Business validation lives in pure
classes (`StaffStatus.allowedTransitions`, `TeacherAssignmentRules`) so it
is unit-tested without Firestore — keep new validation in that shape.
Attendance widget tests use `FakeStudentAttendanceRepository`,
`FakeStaffAttendanceRepository` and `FakeCalendarRepository`
(`test/support/attendance_fakes.dart`); concurrency, partial-save and
correction logic lives in pure classes (`AttendanceSheet`,
`AttendanceSavePlanner`) and is unit-tested directly. Keep a status-driven
UI test from calling `pumpAndSettle` while a save spinner is on screen — it
never settles; use `pump` with a duration.
No Dart Firestore fake (`fake_cloud_firestore`) is used: the current
release does not compile against the pinned Flutter SDK's `meta`.

`test/widget/app_smoke_test.dart` overrides `authRepositoryProvider` (and,
since Milestone 1, `userRepositoryProvider`/`schoolRepositoryProvider`)
with fakes specifically so tests never touch real Firebase — see
`test/support/fakes.dart`, and follow that pattern for any new test that
exercises auth- or tenant-gated UI.

**Gotcha**: reading an `AsyncNotifierProvider`'s `.future` from a bare
`ProviderContainer` (not a widget tree) needs an active
`container.listen(...)` held for the duration of the read, or the
auto-dispose provider can be torn down before its value arrives and the
future hangs forever. See the comment on `_resolveTenant` in
`test/core/tenant_context_provider_test.dart`. This only affects
container-based unit tests — widgets are unaffected, since `ref.watch` in
a `build()` method already keeps a provider alive.

## Firestore security rules — testing

Rules tests live in `firestore-tests/` (a separate Node project — not
part of the Flutter app's dependency tree) and run against the local
Firestore + Storage emulators, so they work without a real Firebase
project:

```
cd firestore-tests
npm install                                    # first time only
cd ..
firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && npm test"
```

The `--project` value must be **exactly** `demo-eazy-school-360` (matching
the `projectId` hardcoded in every `firestore-tests/*.test.mjs` file) — `firebase.json` sets `"singleProjectMode":
true`, which silently coerces every emulator call (including
`storage.rules`' `firestore.get()` cross-service lookups) onto whatever
project the CLI's `--project` flag specifies. A mismatch doesn't error —
it makes every rule check that depends on the caller's Firestore profile
resolve to `false` (deny), so "should succeed" tests fail while "should
fail" tests keep passing. If you ever change that constant, change it in
all test files and this command together. The test files run in parallel
against one shared emulator and do not clear it, so a new file must use its
own school ids and user ids (`staff-rules.test.mjs` does — `st-a-<n>` per
test, `stf-` uid prefix) or it can interfere with the others.

These are the tests that actually demonstrate tenant isolation (School A
can't read School B's data, a disabled account is denied, a user can't
escalate their own role, only `manageSchool` holders can upload their
own school's logo, a parent can read only their own linked child and
nobody else's, ...) — see `MULTI_TENANT_GUIDE.md` → "Security rules",
`docs/milestone-2-school-setup.md`, and
`docs/milestone-3-student-parent-management.md` for what the rules
themselves do, and add a new test here whenever a rule changes.

Milestone 5 adds `firestore-tests/attendance-rules.test.mjs` (student and
staff attendance: tenant/branch isolation, class-teacher scope, revision,
finalization, history, roster query); it uses `att-a-<n>` school ids and an
`att-` uid prefix. If a rules run hangs or a previously green test fails,
check for orphaned emulator or `node --test` processes from an aborted run
(`pkill -f "node --test"; pkill -f "firebase emulators"`) — a stale process
sharing the emulator corrupts results.

Milestone 4 adds `firestore-tests/staff-rules.test.mjs` (staff,
departments, designations, employee-code uniqueness, teacher assignments,
class-teacher and subject slots, lifecycle, documents) and
`staff-storage-rules.test.mjs` (staff photo and documents). To run just one
file: `firebase emulators:exec --only firestore,storage --project
demo-eazy-school-360 "cd firestore-tests && node --test staff-rules.test.mjs"`.
Prefer asserting both an allowed and a denied case for any new rule, and
check a denial test really fails without the rule it covers.

## Building

```
# Web
flutter build web --release

# Android (debug config validated this milestone; release signing not yet configured)
flutter build apk --debug
flutter build appbundle --release   # once a release signing config exists

# iOS (requires a Mac + Xcode; code signing not yet configured)
flutter build ios --release
```

## Coding conventions

- Feature-first under `lib/features/<feature>/{data,domain,presentation}` —
  see PROJECT_ARCHITECTURE.md for the full rationale.
- A widget never calls `FirebaseFirestore.instance`/`FirebaseAuth.instance`/
  `FirebaseStorage.instance` directly — route through a repository in that
  feature's `data/` layer, injected via a Riverpod provider.
- Every async operation models idle/loading/success/empty/error — use
  `AsyncNotifier` + `AsyncValueWidget` (or `AsyncValue.when` directly) rather
  than ad hoc `isLoading`/`hasError` booleans.
- Reach for `core/theme` tokens and `Theme.of(context)` — no raw
  `Colors.black`/hardcoded hex values in feature code.
- Every new top-level screen must be checked against the responsive
  checklist in the `flutter-professional-development` skill (mobile,
  tablet, desktop, both orientations, keyboard open).
- Run `flutter analyze` clean before considering any change done.

## Firebase security rules — deploying

`firestore.rules` enforces tenant isolation for `/users`, `/schools`,
`/schools/{schoolId}/branches`, the academic structure, and students/
parents (see MULTI_TENANT_GUIDE.md); `storage.rules` has rules for the
school logo and student/parent photo paths and otherwise default-denies
everything. `firestore.indexes.json` (Milestone 3) holds the composite
indexes the student/parent list and collection-group queries need. Deploy
all three with:

```
firebase deploy --only firestore:rules,firestore:indexes,storage:rules --project <project-id>
```

(No `.firebaserc` is committed — pass `--project` explicitly, or create a
local, gitignored `.firebaserc` mapping aliases to your project IDs.)

## Google Sign-In setup (per environment, once a real Firebase project exists)

Code is complete (`FirebaseAuthRepository.signInWithGoogle()`), but it
cannot succeed until, per environment:

1. Android: register that build's SHA-1/SHA-256 fingerprint
   (`cd android && ./gradlew signingReport`) against the Firebase project,
   then re-run `flutterfire configure` for that environment.
2. iOS: add the `REVERSED_CLIENT_ID` URL scheme to
   `ios/Runner/Info.plist` — `flutterfire configure` or the Google
   Sign-In iOS setup docs generate the exact value once a real project
   exists.
3. Web: no extra setup — Firebase's own popup flow handles it once the
   project exists.

See SECURITY_ARCHITECTURE.md → "Google Sign-In" for why this can't be
done ahead of a real project existing.

## Fees tests (Milestone 6)
`firestore-tests/fees-rules.test.mjs` runs with the other rules files. Use project id `demo-eazy-school-360`; Storage rules fail with another id because of cross-service lookups.

## Leave tests (Milestone 7)
`firestore-tests` now runs its files **serially** (`node --test --test-concurrency=1`, set in `package.json`): every file shares one emulator project and, in parallel, unrelated Storage tests became flaky. `leave-contract.test.mjs` replays `fixtures/leave-write-plans.json`, which is generated by `flutter test test/leave/leave_write_contract_test.dart` — regenerate it after changing what the Dart leave code writes, then run the rules suite.

## Timetable tests (Milestone 8)
`timetable-contract.test.mjs` replays `fixtures/timetable-write-plans.json`, generated by `flutter test test/timetable/timetable_write_contract_test.dart`; regenerate it after changing what the Dart timetable code writes, then run the rules suite. Format only the files you changed (`dart format <paths>`), not `lib/` as a whole.

## Homework tests (Milestone 9)
`homework-contract.test.mjs` replays `fixtures/homework-write-plans.json`, generated by `flutter test test/homework/homework_write_contract_test.dart`; regenerate it after changing what the Dart homework/announcement code writes, then run the rules suite. Firestore rules have a 1000-expression evaluation budget per request: the submission update rule uses most of it, so prefer the profile-based helpers (`profileManages`, `profileTeachesHomework`, `profileIsLinkedParent`) and `let` bindings, and re-run the mutation checks listed in the milestone doc after changing them. Storage objects persist across tests in one emulator run — use distinct object names.
## Examination tests (Milestone 10)
`exam-contract.test.mjs` replays `fixtures/exam-write-plans.json`, generated by `flutter test test/exams/exam_write_contract_test.dart`; regenerate it after changing what the Dart examination code writes. All grading arithmetic lives in `ResultCalculator` — change it only with tests in `test/exams/exam_domain_test.dart`. Marks are written five entries per commit (`kMarksBatchSize`) because each entry carries an enrolment lookup in the rules. Name every expected denial in rules tests (`denied(n, …)`): a helper that silently ignores a mis-shaped override makes a "denied" case pass for the wrong reason.

## Notification and communication tests (Milestone 11)
`flutter test test/communication test/widget/communication_ui_test.dart`; rules: `communication-rules.test.mjs`, `communication-storage-rules.test.mjs`, `communication-contract.test.mjs` (regenerate its fixture with `flutter test test/communication/communication_write_contract_test.dart`). Run the rules suite serially (shared emulator project id).

## Release signing and CI (Milestone 12)
Android release builds read `android/key.properties` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it the build is signed with the debug key (a Gradle warning is logged but Flutter's filtered output may hide it) — never publish such a build; verify with `apksigner verify --print-certs`. UAT/prod entry points refuse to start while their Firebase options are still the `REPLACE_WITH_FLUTTERFIRE_CONFIGURE` placeholders. CI (`.github/workflows/ci.yml`) runs format, analyze, tests, a release web build and the serial rules suite. Tenant sweeps: `tenant-sweep.test.mjs`, `tenant-sweep-storage.test.mjs` (they discover new collections automatically).
