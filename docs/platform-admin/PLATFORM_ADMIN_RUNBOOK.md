# Platform admin: setup and operations runbook

Applies to Phase 0-1 of `PLATFORM_ADMIN_PLAN.md` (identity, two-step verification,
platform admins screen). Decisions taken 2026-11-13: first account
`admin@avail404.com`; password plus two-step verification (authenticator app);
schools get on/off status only (no plans); manual billing; schools are told when
support accesses their data (Phase 2).

## What changed in behaviour
- A platform admin (`role: PLATFORM_ADMIN`) is **refused by every rule and callable unless
  the session was signed in with a second factor** (`firebase.sign_in_second_factor`
  on the token). This covers Firestore, Storage, the branding callables, account-deletion
  review/processing and the new platform callables.
- A platform admin cannot use the school app (they have no school). They land on
  `/platform` (platform home). Without a second factor the app only shows `/platform/mfa`.
- Clients can no longer write `/users/{uid}` as a platform admin (the old blanket
  `isPlatformAdmin()` update clause was removed). Platform admins are created, re-roled
  and disabled only by the callables below, each writing a `platformAuditLog` record.
- Profiles written before `platformRole` existed are treated as `OWNER` until an owner assigns a role.

## One-time prerequisite per Firebase project (dev and prod)
Authenticator-app (TOTP) two-step verification needs **Identity Platform**:
1. Firebase console -> Authentication -> Settings (or "Upgrade to Identity Platform" banner) -> upgrade the project.
2. Authentication -> Sign-in method -> Advanced -> **Multi-factor authentication** -> Enable,
   and turn on **Time-based one-time password (TOTP)**.
3. Authentication -> Settings -> Authorized domains: confirm the hosting domains are listed.

Do this **before** deploying rules/functions, otherwise nobody can enrol a second factor and any
existing platform admin is locked out of the app (the console and Admin SDK still work).

## Creating the first platform admin (bootstrap)
Needs project credentials (`gcloud auth application-default login`, or `GOOGLE_APPLICATION_CREDENTIALS`).

```
node tool/create_platform_admin.js --project eazy-school-360-dev  --email admin@avail404.com --name "Avail404 Admin" --role OWNER --dry-run
node tool/create_platform_admin.js --project eazy-school-360-dev  --email admin@avail404.com --name "Avail404 Admin" --role OWNER
node tool/create_platform_admin.js --project eazy-school-360-prod --email admin@avail404.com --name "Avail404 Admin" --role OWNER --yes
```
- It prints a one-time password-reset link. Give it only to the person, over a private channel.
- Only `@avail404.com` addresses are accepted. To allow another domain set
  `PLATFORM_ADMIN_EMAIL_DOMAINS=avail404.com,other.example` in `functions/.env.<project>` (callable) or in the shell (script).
- The Auth user is created with a verified email (required to enrol a second factor) and a random password nobody knows.

Then the person: opens the link and chooses a password -> signs in at the app -> is taken to
**Two-step verification** -> scans the QR code with an authenticator app, enters the first code ->
signs out and signs in again with the code (Firebase only puts the second factor on the token at sign-in).

## Adding more platform admins
Platform home -> Platform administrators -> Add administrator (owner only). The person is emailed a
password-setup link and goes through the same two-step setup. Use **Send setup email** to resend.
Roles: `OWNER`, `SUPPORT`, `COMPLIANCE`, `VIEWER` (see the plan). An owner cannot change or disable their own account.

## Recovery
- Lost authenticator app: another **owner** cannot reset it from the app. Use the Firebase console
  (Authentication -> user -> remove the second factor), then the person enrols again.
- No owner left: run the bootstrap script with a new address (needs project credentials), or recreate the profile
  by hand. Keep one sealed break-glass owner whose credentials are in the company vault.
- Suspected misuse: disable the account (platform admins screen), then review `platformAuditLog`.

## Deploy order for this change
1. Enable MFA (above) on the target project.
2. `firebase deploy --only functions --force --project <p>` (new callables, MFA check in `access.js`).
3. Hosting (the setup screens must be live before anyone signs in): `flutter build web --release -t lib/main_<env>.dart --dart-define=APP_ENV=<env>` then `firebase deploy --only hosting --project <p>`.
4. Rules last: `tool/deploy_rules.sh <p> --dry-run`, then `tool/deploy_rules.sh <p>`.
5. Create the first platform admin (script above), then sign in as them, set up two-step and open Platform administrators.

## Audit log
`platformAuditLog` (create-only, written by Cloud Functions). Readable (second factor required) by `OWNER`
and `COMPLIANCE` through the rules; a viewer screen arrives in Phase 2. Records hold actor, action, target, result,
source (`CALLABLE` or `SCRIPT`) and never passwords, links or tokens.
