# Production configuration audit

**Repository evidence** = files in git. **Cloud evidence** = verified in the real console/project. This audit had no cloud access, so every "cloud" cell is UNKNOWN — REQUIRES VERIFICATION unless stated.

| Area | Repository evidence | Cloud evidence | Verdict |
|---|---|---|---|
| Environment separation | `main_dev/prod` + validator reject cross-env options; `main.dart` needs `APP_ENV`; test/uat refuse to start | project ids really `eazy-school-360-dev/-prod`? UNKNOWN | repo ✔ |
| **Staging** | none (`test`/`uat` are placeholders) | — | ✘ no pre-production environment (blocker for cutover rehearsal) |
| Firestore rules & indexes versioned | `firestore.rules` (223,727 B), `firestore.indexes.json` (91 + 3) | deployed version UNKNOWN; team tool says full-file release refused | ✘ SEC-1 |
| Storage rules | `storage.rules` | deployed? Storage enabled in both projects? UNKNOWN | UNKNOWN |
| Rules deployment process | manual `firebase deploy`; no workflow, no `.firebaserc` (by design), no dry-run in CI | — | ✘ not repeatable |
| Functions | `functions/` Node 22; region `asia-south1` (`FUNCTIONS_REGION`); only `maxInstances:10` set; no timeout/memory | deployed, secrets (`META_WA_ACCESS_TOKEN`, `OTP_PEPPER`), `.env` values UNKNOWN | UNKNOWN |
| App Check | client opt-in define, server `ENFORCE_APP_CHECK` default false | registration & metrics UNKNOWN | ✘ off by default (SEC-2) |
| Android signing | `key.properties` loader; **debug fallback** (`build.gradle.kts:62-71`) | upload keystore / Play App Signing UNKNOWN | ✘ CFG-1 |
| Android manifest | channel `eazyschool_general`, `POST_NOTIFICATIONS`; no `INTERNET` in main manifest (merged by plugins — verify with `aapt dump permissions`), `allowBackup` default | — | CFG-3 |
| iOS | `aps-environment=development` in entitlements (Xcode re-signs for App Store), no `PrivacyInfo.xcprivacy`, no usage strings | APNs auth key in Firebase, certificates, iOS 26.5 platform on build Mac UNKNOWN | UNKNOWN |
| Web push | service worker `no-cache`, no secrets in SW; VAPID via `FCM_VAPID_KEY` define | key in CI/build? UNKNOWN (CI build passes none) | UNKNOWN |
| Hosting | headers: HSTS, nosniff, DENY framing, referrer, permissions; SPA rewrite; **no CSP**; `no-cache` on shell | custom domain, certificate, authorised domains, OAuth redirect URIs UNKNOWN | CFG-4 |
| Google/OAuth | `google_sign_in` 7 | OAuth consent, SHA-1/256, web client IDs UNKNOWN | UNKNOWN |
| API key restrictions | public keys committed (by design) | referrer / app restrictions UNKNOWN | UNKNOWN |
| Crash reporting | `firebase_crashlytics` + Dart sink (release, mobile only, opt-out define) | **no** Crashlytics Gradle plugin, no iOS symbol upload, no verification crash | ✘ OPS-2 |
| Alerting | docs only (`docs/app-check-and-monitoring.md`) | Cloud Monitoring policies, budget alerts UNKNOWN | ✘ OPS-3 |
| Backups | commands documented only | PITR / schedules / storage versioning / restore drill UNKNOWN | ✘ OPS-1 |
| TTL | `pushDeliveries.expireAt` override | enabled? UNKNOWN; none for `otpChallenges/otpRate` | SEC-3 |
| CI/CD | 3 jobs (flutter, rules, functions); web build uses `main.dart` not prod entry; no Android/iOS job; no `permissions:`; actions on tags; no dependabot/CODEOWNERS | branch protection UNKNOWN | CFG-7/8 |
| Reproducible builds | `pubspec.lock`, `functions/package-lock.json`, `firestore-tests/package-lock.json` committed; Flutter pinned in CI | — | ✔ |
| Versioning | `pubspec` `version`; release/build metadata process undocumented | — | minor |
| Rollback | rules rollback documented (redeploy previous); app rollback = previous build; no data rollback besides PITR (unverified) | — | partial |

## Required environment values before launch (names only)
`APP_ENV`, `FUNCTIONS_REGION`, `FCM_VAPID_KEY`, `APP_CHECK_ENABLED`, `APP_CHECK_WEB_KEY`, `CRASH_REPORTING`; functions: `ENFORCE_APP_CHECK`, `META_WA_PHONE_NUMBER_ID`, `META_WA_TEMPLATE_NAME`, secrets `META_WA_ACCESS_TOKEN`, `OTP_PEPPER`; Android `key.properties`; Apple signing assets. Not inspected for values.
