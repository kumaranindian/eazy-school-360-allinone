# Firebase environment configuration

Status (2026-10-10): **dev and prod — configured for web, Android and iOS
(web and Android builds verified; iOS builds blocked by the missing Xcode
platform); test / uat — intentionally unconfigured (refuse to start).**

## 1. Project mapping (what is in the repository)

| Environment | Firebase project id | Web | Android | iOS |
|---|---|---|---|---|
| `dev` | `eazy-school-360-dev` | configured | configured | configured |
| `prod` | `eazy-school-360-prod` | configured | configured | configured |
| `test`, `uat` | none | — | — | — |

Application identifier (Android `namespace`/`applicationId`, iOS bundle id,
and the registered Firebase apps): `com.avail404.eazyschool.eazyschool360`.

Files discovered and where they are now:

| Source file (as supplied) | Now at | Used for |
|---|---|---|
| `google-services_eazy-school-dev.json` | `config/firebase/dev/dev.google-services.json` | reference; values copied into `firebase_options_dev.dart` and checked by a test |
| `GoogleService-Info-eazy-school-dev.plist` | `config/firebase/dev/dev.GoogleService-Info.plist` | same |
| web snippets (dev, prod) | values in `firebase_options_dev.dart` / `firebase_options_prod.dart` | Flutter web |
| `google-services-eazy-school-prod.json` | `config/firebase/prod/prod.google-services.json` | same, for prod |
| `GoogleService-Info-eazy-school-prod.plist` | `config/firebase/prod/prod.GoogleService-Info.plist` | same, for prod |

Verified for **both** dev and prod (by `test/core/firebase_environment_test.dart`): project id,
project number (= messaging sender id), storage bucket, Android app id and
package name, iOS app id and bundle id, and API keys equal the Dart options.
The web options were taken from the supplied snippets; the web app id's project
number equals the Android/iOS project number. Analytics (`measurementId`) is
recorded in the web options but the app does not use Firebase Analytics.

## 2. How an environment is selected

One mechanism, no defaults:

1. **Entry point** — `lib/main_dev.dart`, `lib/main_prod.dart` (and
   `main_test.dart` / `main_uat.dart`, which refuse to start). Each calls
   exactly one factory in `lib/core/config/env/environments.dart`, so a
   production build compiles only its own options.
2. **`--dart-define=APP_ENV=dev|prod`** — optional on the dedicated entry
   points (must agree with them, else `ENV_DEFINE_MISMATCH` / `ENV_INVALID`);
   **required** by the generic `lib/main.dart` (`ENV_NOT_SELECTED` without it).

Startup (`lib/app/bootstrap.dart` → `FirebaseInitializer`) then:
validates the selected options for the running platform → refuses a leftover
default Firebase app of another project → initialises Firebase **once** →
verifies the active project id equals the selected environment's → starts the
app. Any failure shows `StartupErrorApp` with a stable code (no keys, no stack
trace) and logs detail via `AppLogger`.

Validation codes: `PLACEHOLDER_*`/`MISSING_*` (incomplete options),
`ENV_PROJECT_MISMATCH` (the environment resolved another environment's
project — dev ↔ prod ids are listed in `known_firebase_projects.dart`),
`APP_ID_PLATFORM`, `APP_ID_SENDER_MISMATCH`, `APP_ID_FORMAT`,
`MISSING_AUTH_DOMAIN`, `AUTH_DOMAIN_PROJECT`, `IOS_BUNDLE_ID`,
`ENV_APP_ALREADY_INITIALISED`, `ENV_ACTIVE_PROJECT_MISMATCH`,
`FIREBASE_INIT_FAILED`.

## 3. Commands

```bash
# development
flutter run -t lib/main_dev.dart --dart-define=APP_ENV=dev -d chrome
flutter run -t lib/main_dev.dart --dart-define=APP_ENV=dev -d <android|ios-device>
flutter build web  --release -t lib/main_dev.dart  --dart-define=APP_ENV=dev
flutter build apk  --debug   -t lib/main_dev.dart  --dart-define=APP_ENV=dev

# production
flutter build web  --release -t lib/main_prod.dart --dart-define=APP_ENV=prod
flutter build apk  --release -t lib/main_prod.dart --dart-define=APP_ENV=prod      # needs signing + prod Android options
flutter build appbundle --release -t lib/main_prod.dart --dart-define=APP_ENV=prod
flutter build ipa  --release -t lib/main_prod.dart --dart-define=APP_ENV=prod      # needs signing + prod iOS options
```

There are deliberately **no Android product flavors and no Xcode scheme
changes** (see §4–5). The environment is selected in Dart, once, by the entry
point.

## 4. Android

* `namespace` and `applicationId` are `com.avail404.eazyschool.eazyschool360`
  (unchanged; matches the registered Firebase Android app).
* Firebase is initialised from the Dart options (`FirebaseOptions` for
  Android in the environment's options file). The Google Services Gradle plugin
  is **not** applied: it would add a second source of truth that could
  disagree with the Dart options, require flavors (every Android build would
  then need `--flavor`), and fail the production build because the prod
  `google-services.json` does not exist. The supplied JSON is kept as a
  checked reference instead.
* Release signing is unchanged: `android/key.properties` (git-ignored); without
  it the release build is **debug-signed and not publishable**.
* **Google Sign-In on Android is not configured**: the supplied dev JSON has
  no OAuth client (no SHA-1 registered). To enable: register SHA-1/SHA-256,
  enable Google in Authentication, re-download the JSON, and supply the web
  client id to the app (`GoogleSignIn.instance.initialize(serverClientId: …)`).
  Email/password is unaffected.

## 5. iOS

* Bundle id `com.avail404.eazyschool.eazyschool360` in all Runner
  configurations (checked by test) — equals the plist's `BUNDLE_ID`.
* Dart options initialise the native Firebase app, so no plist is bundled
  (this also avoids two competing configurations). Xcode project, signing and
  URL schemes were not modified.
* The supplied dev plist has no `CLIENT_ID`/`REVERSED_CLIENT_ID`, so Google
  Sign-In is not configured on iOS either (same owner action as Android).
* **iOS builds could not be run**: this Mac has no iOS 26.5 platform
  (`flutter build ios` → "iOS 26.5 is not installed"). The iOS configuration is
  therefore **configured but unverified by a build**.

## 6. Web

* `web/index.html` contains no Firebase JavaScript; Firebase is initialised
  once, from Dart (`Firebase.initializeApp(options: …)`), for Auth, Firestore
  and Storage alike. Nothing in `index.html` needs the web config.
* Web options include `authDomain`, `storageBucket`, `measurementId`.
* Authorised domains and OAuth redirect settings are console settings and were
  not touched. Add the hosting domain(s) for each project.
* No web push configuration exists or was added.

## 7. Updating an environment (FlutterFire)

1. `flutterfire configure --project=<id> --out=/tmp/firebase_options_<env>.dart`
   (scratch output — do **not** point `--out` at the repository option file;
   it generates a different shape).
2. Copy each platform's `FirebaseOptions(...)` into the matching block in
   `lib/core/config/firebase_options/firebase_options_<env>.dart`.
3. Save the native files to `config/firebase/<env>/` (`<env>.google-services.json`,
   `<env>.GoogleService-Info.plist`) and extend
   `test/core/firebase_environment_test.dart` the way the dev tests do.
4. A platform without its file keeps `REPLACE_WITH_FLUTTERFIRE_CONFIGURE`
   values; that build then stops at startup (`PLACEHOLDER_*`) — it never falls
   back to another environment.

## 8. Verifying the active project safely

* Startup logs one line through `AppLogger`: `env=<name> project=<id> app=<masked>`
  (no key, no full app id) — `EnvConfig.diagnostics()`.
* The initializer fails the start if the active project differs from the
  selected environment's.
* Inspect a built web bundle: `grep -c '<project-id>' build/web/main.dart.js`
  and compare API-key *prefixes* against the intended environment.

## 9. Verification performed (2026-10-10)

| Platform / environment | Build | Result | Mapping check |
|---|---|---|---|
| Web dev | `flutter build web --release -t lib/main_dev.dart --dart-define=APP_ENV=dev` | ✓ | bundle contains the 3 dev API keys and no prod key |
| Web prod | `flutter build web --release -t lib/main_prod.dart --dart-define=APP_ENV=prod` | ✓ | bundle contains the 3 prod keys and no dev key |
| Android dev | `flutter build apk --debug -t lib/main_dev.dart --dart-define=APP_ENV=dev` | ✓ | contains dev keys (a debug build also carries other libraries' code) |
| Android prod | `flutter build apk --release -t lib/main_prod.dart --dart-define=APP_ENV=prod` (also `appbundle`) | ✓ built (68.1 MB / 52.4 MB), **debug-signed** — no `key.properties` | contains the prod Android key and app id (`1:97832195228:android:…`), no dev keys or ids, no placeholders |
| iOS dev / prod | `flutter build ios --no-codesign …` | ✗ blocked: iOS 26.5 platform not installed | not verified |

Every build above embeds both project id *strings* (they are the guard
constants); API keys and app ids are per environment.

Tests: `flutter test` **904 passed** (882 before; +22 in
`test/core/firebase_environment_test.dart`: environment parsing, dev/prod
options, missing/placeholder options, project mix-up, app-id/platform checks,
single initialisation with the right options, leftover app, active-project
check, safe failure, native-file consistency). `flutter analyze` clean. The
Firebase emulator rules suite was not re-run (no rules changed; last full run
290/290).

## 10. Platform status

| | dev | prod |
|---|---|---|
| Web | **configured, build verified**; not exercised against the live project | **configured, build verified**; not exercised against the live project |
| Android | **configured, build verified**; Google Sign-In not configured | **configured, build verified (debug-signed — not publishable without a keystore)**; Google Sign-In not configured |
| iOS | **configured, build NOT verified** (platform missing); Google Sign-In not configured | **configured, build NOT verified** (platform missing); signing not set up |

"Configured" means the options and native registrations are present,
mutually consistent and tested; it does **not** mean the app has been run
against the live Firebase project or published.

## 11. Owner-supplied items still missing

1. Release keystore (`android/key.properties`) and iOS signing identity.
2. For Google Sign-In on mobile (both projects): SHA-1/256 registration,
   Google provider enabled, re-downloaded native files (the supplied ones have
   no OAuth client), and the web client id.
3. The iOS 26.5 platform on the build Mac to verify iOS builds.
4. Authorised domains for each project's web hosting.
5. Decision on `test` / `uat`: supply projects or leave unconfigured.
6. First run against each live project (sign-in, a Firestore read, a Storage
   upload) — not performed here by design.
