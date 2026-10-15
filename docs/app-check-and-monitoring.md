# App Check and crash reporting

Both are **opt-in and off by default**, so nothing changes for existing builds until you switch them on.

## App Check (abuse protection for the callables)

Callables (`requestPhoneOtp`, `verifyPhoneOtp`, `provisionLogins`, `setLoginAccess`, …) can reject requests that
don't come from a genuine app. Two independent switches, enabled in this order:

1. **Send tokens (app).** Build with `--dart-define=APP_CHECK_ENABLED=true`. Web also needs
   `--dart-define=APP_CHECK_WEB_KEY=<reCAPTCHA v3 site key>` (without it, web skips App Check and logs a warning).
   Android uses Play Integrity, iOS App Attest with DeviceCheck fallback; debug builds use the debug providers
   (register the debug token printed in the console under App Check → Apps → Manage debug tokens).
2. **Register the apps** in Firebase Console → App Check (Play Integrity for Android, App Attest/DeviceCheck for iOS,
   reCAPTCHA v3 for web). Watch the App Check metrics until verified traffic is ~100%.
3. **Enforce (functions).** Set `ENFORCE_APP_CHECK=true` in `functions/.env.<projectId>` (see `functions/env.example`)
   and redeploy functions. Do this only after step 2 shows all supported app versions sending tokens; older builds
   without tokens will then be rejected. Rollback: set it to `false` and redeploy.

Firestore/Storage App Check enforcement is a separate console toggle and is not changed by this.

## Crash reporting (Crashlytics)

* The app reports every `AppLogger.error(...)` and all unhandled Flutter/platform errors (non-fatal records) from
  **release builds on Android and iOS**. Web, debug builds and tests report nothing. Opt out with
  `--dart-define=CRASH_REPORTING=false`.
* Never log personal data in `AppLogger` messages or errors — they now leave the device.
* **Native setup still required (not done here, cannot be built in this environment):**
  * Android: add the `com.google.firebase.crashlytics` Gradle plugin (and the Google services plugin it expects,
    fed from `config/firebase/<env>/<env>.google-services.json`) in `android/settings.gradle.kts` /
    `android/app/build.gradle.kts`. Without it Crashlytics has no build ID and Android reports will not arrive.
  * iOS: add the "Upload Symbols" run-script build phase (see the FlutterFire Crashlytics guide) and enable
    Crashlytics for the project in the console.
  * Verify once per environment with a test crash from a release build and confirm it in the console.
* Alerts: in Google Cloud Monitoring, create alert policies for Cloud Functions errors (`severity>=ERROR`, execution
  failures of `requestPhoneOtp`/`verifyPhoneOtp`/`pushNotification`) and a billing budget alert on each project.

## CI

`.github/workflows/ci.yml` now has a `functions` job that runs `npm ci && npm test` in `functions/`.
