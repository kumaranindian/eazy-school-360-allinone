# Android production release

Application id (stable, never change): `com.avail404.eazyschool.eazyschool360`.
Target/compile SDK: 36 (Google Play requires targetSdk 36 for new apps and
updates from 2026-08-31). Prod Firebase project: `eazy-school-360-prod`.

## 1. Create the upload keystore (once, on your own machine)

Keep it OUTSIDE the repository (e.g. `~/secure/`), back it up in two places
(password manager + offline copy). Losing the upload key means a Play support
request to reset it; leaking it means anyone can upload as you.

```
mkdir -p ~/secure && keytool -genkeypair -v \
  -keystore ~/secure/eazyschool360-upload.jks \
  -storetype PKCS12 \
  -alias eazyschool360-upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=EazySchool 360, O=Avail404, C=IN"
```

keytool prompts for the passwords; choose strong ones. Then:

```
cp android/key.properties.example android/key.properties   # git-ignored
# edit: storeFile=/Users/<you>/secure/eazyschool360-upload.jks, passwords, alias
keytool -list -v -keystore ~/secure/eazyschool360-upload.jks -alias eazyschool360-upload | grep -E "SHA1|SHA256"
```

## 2. Register the certificate fingerprints in Firebase

Firebase console -> `eazy-school-360-prod` -> Project settings -> Android app
-> Add fingerprint: the upload key's SHA-1 and SHA-256. After the first Play
upload, also add the **Play App Signing** key's SHA-1/SHA-256 (Play Console ->
App integrity -> App signing). Without both, Google sign-in / Play Integrity
(App Check) fail in the store build.

## 3. Build

```
flutter build appbundle --release -t lib/main_prod.dart \
  --dart-define=APP_ENV=prod \
  --dart-define=APP_CHECK_ENABLED=true \
  --build-name=1.0.0 --build-number=<increasing integer>
```

Output: `build/app/outputs/bundle/release/app-release.aab`.
Every Play upload needs a higher `--build-number` than the last.

Without `android/key.properties` the build fails on purpose
(`-PallowDebugSignedRelease=true` is for local, non-publishable checks only).

## 4. Verify the artifact

```
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab | head -20
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab   # SHA-256 must equal the upload key
```
Must NOT show `CN=Android Debug`. Check id/version/targetSdk with bundletool
(`bundletool dump manifest --bundle=...`).

## 5. Backend dry-runs (nothing is deployed by these)

```
tool/deploy_rules.sh eazy-school-360-prod --dry-run
firebase deploy --only firestore:indexes,functions --project eazy-school-360-prod --dry-run
```
Real deploys need explicit approval and the order in
`docs/production-audit/DEPLOYMENT_CHECKLIST.md` (app -> backfills -> rules).

## Findings from the 2026-10-19 dry-runs against `eazy-school-360-prod`

- Firebase Storage is **not set up** on prod: open the console Storage page and
  click Get Started (pick the production region) before deploying `storage.rules`.
- Prod is **not on the Blaze plan**: Cloud Functions (push, OTP, access) cannot
  deploy until it is upgraded.
- Note: even with `--dry-run`, the Firebase CLI enables required Google APIs
  (firebasestorage, cloudfunctions, cloudbuild, artifactregistry) on the project.
