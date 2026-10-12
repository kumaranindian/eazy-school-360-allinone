# Package / Application Identity Migration Report

Scope: rebrand the platform-foundation (Milestone 0) project to the
**Avail404** organization under the application identifier
`com.avail404.eazyschool.eazyschool360`, with user-facing product name
**EazySchool 360**. No business logic, Firestore schema, auth flow, or
feature behavior was touched — this is identity/branding only.

Repository note: this project currently has **zero git commits** (all
Milestone 0 and migration work exists as uncommitted files). There is
therefore no prior commit to diff against — this document, together with
the Milestone 0 summary earlier in the project history, is the record of
what changed.

## Identifiers — before and after

| Identifier | Old | New |
|---|---|---|
| Dart/pub package name | `eazy_school_360` | **unchanged** — `eazy_school_360` |
| Android `namespace` | `com.eazyschool.eazy_school_360` | `com.avail404.eazyschool.eazyschool360` |
| Android `applicationId` | `com.eazyschool.eazy_school_360` | `com.avail404.eazyschool.eazyschool360` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` (Runner) | `com.eazyschool.eazySchool360` | `com.avail404.eazyschool.eazyschool360` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` (RunnerTests) | `com.eazyschool.eazySchool360.RunnerTests` | `com.avail404.eazyschool.eazyschool360.RunnerTests` |
| User-facing app name | `Eazy School 360` | `EazySchool 360` |
| MainActivity package | `com.eazyschool.eazy_school_360` | `com.avail404.eazyschool.eazyschool360` |

**Why the Dart package name did not change:** Flutter/Dart has no
Java-style reverse-domain package requirement — `pubspec.yaml`'s `name:`
only has to be a valid pub package name, and every `package:eazy_school_360/...`
import in `lib/` and `test/` resolves against it. Renaming it would have
touched every import in the codebase for no functional or branding
benefit (it's never shown to a user), so it was deliberately left alone,
per the explicit instruction not to conflate it with the platform
application identifier.

## Files changed

**Android**
- `android/app/build.gradle.kts` — `namespace`, `applicationId`
- `android/app/src/main/AndroidManifest.xml` — `android:label` → `EazySchool 360`
- `android/app/src/main/kotlin/com/eazyschool/eazy_school_360/MainActivity.kt`
  → **moved** to
  `android/app/src/main/kotlin/com/avail404/eazyschool/eazyschool360/MainActivity.kt`,
  `package` declaration updated to match. Old now-empty directories
  (`com/eazyschool/eazy_school_360`, `com/eazyschool`) removed.

**iOS**
- `ios/Runner.xcodeproj/project.pbxproj` — `PRODUCT_BUNDLE_IDENTIFIER`
  updated in all 6 occurrences (Runner × Debug/Release/Profile, RunnerTests
  × Debug/Release/Profile)
- `ios/Runner/Info.plist` — `CFBundleDisplayName` → `EazySchool 360`

**Web**
- `web/manifest.json` — `name`, `short_name`, `description`
- `web/index.html` — `<title>`, `apple-mobile-web-app-title` meta, `description` meta

**Dart source (display strings only — no logic changed)**
- `lib/core/config/env_config.dart` — `appName` strings for all four environments
- `lib/core/routing/app_shell.dart` — `AdaptiveScaffold` title
- `lib/features/authentication/presentation/pages/login_page.dart` — heading text
- `lib/core/config/firebase_options/firebase_options_{dev,test,uat,prod}.dart` —
  placeholder `projectId`/`storageBucket` strings renamed from
  `eazy-school-360-<env>` to `avail404-eazyschool360-<env>` for naming
  consistency. **These files are gitignored and contain no real values** —
  see "Firebase status" below.

**Pubspec / metadata**
- `pubspec.yaml` — `description` (brand wording + Avail404 attribution).
  `name:` left unchanged (see above).

**Tests**
- `test/widget/app_smoke_test.dart` — updated the expected display string
  from `'Eazy School 360'` to `'EazySchool 360'` to match the renamed UI
  text. No test logic/behavior changed.

**Documentation**
- `README.md` — title, Avail404 attribution, application identifier line,
  added a link to this report
- `PROJECT_ARCHITECTURE.md` — intro branding, and a new "Application
  identity" section explicitly tabulating Dart package name vs. Android
  namespace/applicationId vs. iOS bundle id vs. user-facing name (the
  separation the brief asked this migration to make explicit)

## Files/folders intentionally NOT changed

- **`pubspec.yaml` `name:` and every `package:eazy_school_360/...` import**
  in `lib/` and `test/` — the Dart package name is independent of the
  platform application identifier (see above); changing it was out of
  scope and was explicitly warned against.
- **`lib/` top-level structure** (`core/`, `features/`, `shared/`, `app/`)
  — already feature-first from Milestone 0 and already matches the
  requested shape. Not reshuffled to chase exact example filenames (e.g.
  moving `app_router.dart` from `core/routing/` into `app/`) — that would
  be cosmetic churn disconnected from the identity migration, and risked
  violating "do not rebuild the application."
- **`features/authentication` internal layout** — kept flat (`data/`,
  `domain/`, `presentation/` each holding files directly, not subdivided
  into `datasources/models/repositories` or `entities/repositories/usecases`)
  because the feature is still trivial (one repository, one model) —
  forcing that subdivision now would be unused ceremony, which the brief
  itself warns against.
- **`ios/Runner/Info.plist` `CFBundleName`** (`eazy_school_360`) — this is
  an internal bundle-executable-name artifact tied to the Xcode project
  name, not the user-facing name (that's `CFBundleDisplayName`, already
  updated) and not a package/application identifier.
- **`android/app/src/debug/AndroidManifest.xml`,
  `android/app/src/profile/AndroidManifest.xml`** — contain only the
  `INTERNET` permission; no identifiers present.
- **`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`**
  — Flutter-tooling-generated boilerplate under the `io.flutter.plugins`
  namespace (not our app's namespace); regenerated automatically by the
  build, never hand-maintained.
- **`DEVELOPMENT_GUIDE.md`, `SECURITY_ARCHITECTURE.md`,
  `FIRESTORE_ARCHITECTURE.md`** — repo-wide search found no old
  identifier or old product-name references in any of these three files
  to begin with, so nothing required correction there.
- **`firestore.rules` / `storage.rules`** — contain no package/application
  identifiers (they key off Firebase Auth custom claims, not app IDs).
- **Business logic, Firestore schema/field names, auth flow, roles,
  routing behavior, UI functionality** — untouched, per explicit instruction.

## Firebase status

No real Firebase project has ever been registered for this app — there is
no `google-services.json` and no `GoogleService-Info.plist` anywhere in
the repository (confirmed by search; the only `GoogleService-Info.plist`
on disk is a third-party test fixture inside
`ios/Pods/FirebaseCore/.../Tests/Unit/Resources/`, unrelated to this app).
The only Firebase "configuration" that existed before this task was four
gitignored, placeholder `firebase_options_<env>.dart` files containing
literal `'REPLACE_WITH_FLUTTERFIRE_CONFIGURE'` values — i.e., Firebase has
never actually seen either the old or the new identifier.

**Firebase console actions required:** none retroactively — there is no
existing Android/iOS app registration under the old identifier to migrate
or delete. Going forward, when a real Firebase project is provisioned per
`DEVELOPMENT_GUIDE.md` → "Environments", register:
- the Android app with `applicationId` **`com.avail404.eazyschool.eazyschool360`**
- the iOS app with bundle id **`com.avail404.eazyschool.eazyschool360`**

then run `flutterfire configure` as documented there. This is first-time
setup, not a migration.

## Google Sign-In status

Not implemented in this codebase. There is no `google_sign_in` dependency,
no OAuth client configuration, no SHA-1/SHA-256 entries, and no custom URL
scheme wired in either `Info.plist` or the Android manifest. Authentication
in Milestone 0 is Firebase email/password only.

**Google Sign-In actions required:** none now. For the record, if/when
Google Sign-In is added in a future milestone: its Android OAuth client
must be registered against SHA-1/SHA-256 fingerprints tied to
`applicationId` `com.avail404.eazyschool.eazyschool360`, and its iOS OAuth
client/URL scheme must be registered against bundle id
`com.avail404.eazyschool.eazyschool360`. That is new setup work for that
future milestone, not something this migration left broken.

## Other Firebase services reviewed

Crashlytics, Analytics, Cloud Messaging, Dynamic Links, Remote Config, and
App Check are **not** used anywhere in this codebase (only `firebase_core`,
`firebase_auth`, `cloud_firestore`, and `firebase_storage` are
dependencies, and `firebase_storage` itself isn't called by any feature
yet). None of them require console-side migration because none of them
have ever been configured.

## Validation performed

```
flutter clean        ✓
flutter pub get      ✓
flutter analyze      ✓  No issues found!
flutter test         ✓  12/12 tests passed
flutter build web --release        ✓  Built build/web
flutter build apk --debug          ✓  Built build/app/outputs/flutter-apk/app-debug.apk
                                       (merged manifest confirmed
                                       package="com.avail404.eazyschool.eazyschool360")
flutter build ios --debug --no-codesign -t lib/main_dev.dart
                                    ⚠ see "Known risks" below
```

Repository-wide search for every old identifier
(`com.eazyschool`, `eazySchool360`, the old Firebase placeholder project
ids, and the old `Eazy School 360` display string) across
`*.dart .kt .kts .gradle .xml .plist .pbxproj .md .yaml .yml .json .html`
returned **zero matches** outside of `build/`, `.dart_tool/`, and
`ios/Pods/` (third-party/generated, not our source).

## Known risks

- **iOS could not be fully built end-to-end in this environment.**
  `pod install` succeeds and Flutter/Xcode tooling correctly report the
  new identifier (`Building com.avail404.eazyschool.eazyschool360 for
  device (ios)...`), but the final Xcode compile step fails with
  `iOS 26.5 is not installed. Please download and install the platform
  from Xcode > Settings > Components.` This is a pre-existing environment
  limitation on this machine (reproduced identically before this migration,
  with the old bundle id) — not caused by this change, and not something
  this task can fix without downloading a multi-GB platform image.
- **No real-device/simulator run was performed** for either platform —
  validation is build-level (compiles, correct identifiers verified in the
  merged Android manifest and the iOS build log), not a manual smoke test
  on a running app instance.
- Since the repository has no git history, this report (plus the
  Milestone 0 summary earlier in the conversation) is the only "before"
  record — there is no commit to `git diff` against.
- The renamed Firebase placeholder project ids
  (`avail404-eazyschool360-<env>`) are cosmetic only, gitignored, and
  don't correspond to any real Firebase project — nothing to reconcile if
  the real naming convention chosen later differs.

## Summary

| # | Item | Value |
|---|---|---|
| 1 | Dart package name | `eazy_school_360` (unchanged) |
| 2 | Android namespace | `com.avail404.eazyschool.eazyschool360` |
| 3 | Android applicationId | `com.avail404.eazyschool.eazyschool360` |
| 4 | iOS bundle identifier | `com.avail404.eazyschool.eazyschool360` |
| 5 | Files/folders moved | 1 (`MainActivity.kt` to new package path) |
| 6 | Files modified | 18 (see "Files changed" above) |
| 7 | Firebase status | No real project ever registered; nothing to migrate; first-time setup documented |
| 8 | Google Sign-In status | Not implemented; nothing to migrate |
| 9 | Tests/builds executed | analyze ✓, test 12/12 ✓, web build ✓, Android debug build ✓, iOS build blocked by local Xcode platform install (not this migration) |
| 10 | Manual console actions required | None now; register apps under the new identifier when real Firebase projects are provisioned (first-time setup) |
| 11 | Remaining risks | iOS build not fully verified end-to-end locally; no manual device run performed |

**Milestone 1 has not been started**, per instruction.
