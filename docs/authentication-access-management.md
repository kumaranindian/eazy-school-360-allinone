# Authentication & login access management

Per-user control of **who can sign in and how**, enforced by the server, plus
phone sign-in (one-time code over WhatsApp via the Meta Cloud API).

## What was found before the change

| Area | State |
| --- | --- |
| Sign-in | Email+password and Google (`FirebaseAuthRepository`). No phone sign-in, no Meta/WhatsApp code anywhere. |
| Identity ↔ record | `/users/{uid}` profile (role, schoolId, branchId, status). Staff → `staff.userId`, parent → `parents.linkedUserId` + `users.linkedParentId`. |
| Key icon | "Give login access" → `provisionLogins` callable creates the Auth account + profile and sets a random password (people use "Forgot password"). No later management, no disable. |
| Access control | `status` (ACTIVE/INVITED/DISABLED) only. |
| Imports | Student sheet had `email`, `parent_email`; staff sheet had `email` — regex check only. |
| Risk found | `provision.js` adopted any pre-existing Auth account with the same email (pre-registration takeover). Fixed (password replaced + sessions revoked on adoption). |

## Data model (additive, no destructive migration)

```
users/{uid}.login = {            // written ONLY by Cloud Functions (admin SDK)
  enabled:   bool,               // master switch
  methods:   ["PASSWORD"|"GOOGLE"|"PHONE_OTP"],   // what the admin permitted
  effective: [...],              // methods ∩ school-enabled   <- what rules check
  phone:     "+91…"|null,        // E.164, bound for PHONE_OTP (unique across users)
  phoneVerifiedAt?, lastOtpLoginAt?, updatedAt, updatedBy
}
schools/{s}/authSettings/methods = { methods: [...], updatedAt, updatedBy }   // admin-read, server-write
schools/{s}/authAudit/{id}       = security audit trail (no secrets)          // admin-read, server-write
otpChallenges/{id}, otpRate/{key}                                              // no client access at all
```

* A profile **without** `login` is a *legacy* account and keeps working exactly
  as before (any provider, status ACTIVE). No user is locked out on deploy.
* Schools without an `authSettings/methods` doc default to Email+Password and
  Google (today's behaviour). Phone OTP is **off** by default.
* When a school changes its settings, `login.effective` is recomputed for the
  whole school (chunked). Legacy users are materialised only if the new
  settings would actually restrict them.

## Enforcement (server-side, not UI)

1. **Firestore + Storage rules** — `isActiveCaller()` now also requires
   `loginAllowed()`: no `login` map, or `login.enabled` and the token's sign-in
   method ∈ `login.effective`. Method is derived from
   `request.auth.token.firebase.sign_in_provider` (`password`, `google.com`,
   `custom` + claim `via == "PHONE_OTP"`). Google additionally requires a
   verified token email equal to the profile email. A disabled user, or a
   method removed by the user's grant or the school, is refused immediately on
   every read/write, even with a valid Auth account and unexpired token.
2. **Cloud Functions** — `assertAdmin` applies the same gate (a disabled admin
   cannot administer).
3. **Prompt revocation** — narrowing access calls `revokeRefreshTokens`
   (cannot silently refresh). Rules already block the old ID token.
4. `login` / settings / audit / OTP collections are not client-writable
   (rules tests assert it).

Disabling never deletes the Auth account, profile, staff/parent record or any
history.

## Callable functions

| Function | Who | Purpose |
| --- | --- | --- |
| `getLoginAccess` | school/branch admin | name, type, registered mobile/email, status, methods, activation, last login |
| `setLoginAccess` | school/branch admin | enable/disable, choose methods, create the account if missing (email optional for phone-only), audit, revoke |
| `getSchoolAuthSettings` / `updateSchoolAuthSettings` | school admin | school switches; lock-out guard; fan-out recompute |
| `requestPhoneOtp` / `verifyPhoneOtp` | unauthenticated | OTP request / verify → Firebase custom token |
| `provisionLogins` | admins | existing bulk "give login", now writes a `login` map and is hardened |

Rules the server enforces: branch admins cannot manage admins; nobody manages
their own access or a school/platform admin here; a method must be enabled by
the school and the record must have the needed email/phone; a phone number can
be bound to one user only; the last usable administrator can't be locked out.

## Phone OTP (Meta WhatsApp Cloud API)

WhatsApp is only the delivery channel. `functions/otp.js`:

* 6-digit code from `crypto.randomInt`; stored only as `HMAC-SHA256(pepper, id:code)`; challenge is single-use.
* 5 min expiry, 5 attempts then locked, 60 s resend cooldown, 5 requests/phone/hour, 20/IP/hour, a new code supersedes older ones.
* Unknown / disabled / ambiguous numbers get the same reply as valid ones (no enumeration) and nothing is sent.
* After a correct code the grant is re-checked (still enabled, phone unchanged) before `createCustomToken(uid, {via: 'PHONE_OTP'})`. The client never reports success.
* `functions/whatsapp.js` posts an approved template to `POST /{version}/{phone-number-id}/messages`; errors map to `INVALID_RECIPIENT`, `PROVIDER_RATE_LIMIT`, `PROVIDER_AUTH`, `TEMPLATE_ERROR`, `TIMEOUT`, `NETWORK`. Codes/tokens are never logged.
* If Meta is unavailable the app shows an actionable message; only methods explicitly permitted for the user remain usable.

### Manual setup (cannot be done from code)

1. Meta Business: create/verify a WhatsApp Business Account and phone number; note the **phone number ID**.
2. Create and get **approved** an *Authentication* message template (code in `{{1}}`, optionally a copy-code button). Note its **name** and language.
3. Create a **permanent access token** (system user) with `whatsapp_business_messaging`.
4. Store secrets (never in the repo / Flutter / Firestore):
   ```
   firebase functions:secrets:set META_WA_ACCESS_TOKEN --project <id>
   firebase functions:secrets:set OTP_PEPPER           --project <id>   # openssl rand -base64 48
   ```
5. Copy `functions/env.example` → `functions/.env` and fill `META_WA_PHONE_NUMBER_ID`, `META_WA_TEMPLATE_NAME`, `META_WA_TEMPLATE_LANG`, `META_WA_API_VERSION`, `META_WA_TEMPLATE_BUTTON`.
6. The functions' runtime service account needs **Service Account Token Creator** on itself (required by `createCustomToken`).
7. In the Firebase console enable the *Email/Password* and *Google* providers (they cannot be introspected from code).
8. Deploy: `firebase deploy --only functions,firestore:rules,storage --project <id>`. `OTP_PEPPER` and `META_WA_ACCESS_TOKEN` must exist **before** deploying the functions that bind them.
9. Optional: enable Firebase App Check on the callables for extra abuse protection.
10. Sign in as a school admin → Settings → Authentication → switch **Phone** on (refused until step 4–5 are done).

Until configured, Phone stays off; Email and Google behave as before.

## UI

* **Settings → Authentication** (school admins): switches for Email+Password, Google, Phone with configuration status, confirm dialog (warns when removing a method), cancel/save, lock-out errors.
* **Key icon** (Staff list, Parents list, parent link on the student profile): *Login access* dialog — name, type, registered mobile/email, access status, methods, activation, last login; enable/disable, per-user methods (unavailable methods are shown with the reason), confirmation for security-sensitive changes, *Send password setup/reset email*, *Sign out all devices*. The old multi-select "Give login access" bar remains for bulk creation.
* **Login page**: Email+password, Google, and *Sign in with phone (WhatsApp code)*. After sign-in, a user whose access is off or whose method isn't permitted sees a dedicated screen naming the allowed methods.

## Imports

Email columns already existed; now: trimmed + lowercased, stricter format, row-level errors,
duplicates **within the file** (staff email; parent email on different parents — siblings of the same parent may repeat it) and **against existing staff / parent records of the branch** are flagged in the preview (never merged or overwritten). Valid rows can still be imported after the existing confirm dialog; the errors CSV lists the rest. When a login is created and the email already has an Auth account **and** a `/users` profile, that profile is *mapped* to the staff/parent record (role and status kept, `userId` / `linkedUserId` / `linkedParentId` set) provided it is in the same school and branch, has a role the record may hold, and is not linked to another record. Anything else is reported per person as `EMAIL_IN_USE` and never merged. Student `email` is normalised/validated but is not a login.

## Migration / rollout

1. Deploy functions → rules → app (rules first is also safe: legacy profiles pass).
2. Nothing to migrate: no `login` map = legacy behaviour.
3. First time an admin saves Authentication settings or edits a user's access, the `login` map is created for the affected users.
4. Rollback: remove `loginAllowed()` from `isActiveCaller()` in both rules files; data stays harmless.

## Tests

* `functions`: `npm test` (access, OTP, WhatsApp mock; no network, no real OTPs).
* `firestore-tests/login-access-rules.test.mjs` (+ whole suite) via emulators.
* Dart: `test/auth/login_access_test.dart`, `test/widget/login_access_ui_test.dart`, import tests under `test/staff`, `test/features/students`.

## Known limits

* Email/Google provider enablement can't be verified from code.
* Existing-email check covers staff/parent records of the branch (case-sensitive for legacy mixed-case emails), not every Auth account.
* A non-matching Google account signs in to Firebase but has no profile → no data access (existing self-signup route still lets it create a *new* school, unchanged).
* Custom tokens cannot be rate-limited per device; App Check recommended.
* ID tokens already issued stay cryptographically valid up to 1 h, but rules deny them as soon as access changes.

## Deploying Cloud Functions (dev rollout notes)

Learned deploying to `eazy-school-360-dev`:

* **Region.** Functions default to `asia-south1` (`FUNCTIONS_REGION`, matching the app's `FUNCTIONS_REGION` define). Firestore triggers (`pushNotification`, `pushBroadcastNotice`) must be in the **same region as the Firestore database** or they never fire. Check with `firebase firestore:databases:get "(default)" --project <id>`. Older deploys were in `us-central1`; the first deploy after this change deletes those copies and recreates them in the new region (`firebase deploy --only functions --force` is needed non-interactively).
* **Secrets are required to deploy**, even for phone-OTP-off projects, because the functions bind them. Set both before deploying (the CLI enables Secret Manager if needed; allow a minute to propagate):
  ```
  openssl rand -base64 48 | firebase functions:secrets:set OTP_PEPPER --project <id> --data-file -
  printf 'placeholder' | firebase functions:secrets:set META_WA_ACCESS_TOKEN --project <id> --data-file -   # real token when enabling phone OTP
  ```
* **`functions/.env` is required** for non-interactive deploys (copy `functions/env.example`; it is gitignored). Empty `META_WA_PHONE_NUMBER_ID` / `META_WA_TEMPLATE_NAME` keep phone sign-in off.
* Deploy: `firebase deploy --only functions --force --project <id>`, then `--only hosting` after `flutter build web --release -t lib/main_<env>.dart --dart-define=APP_ENV=<env>`.
