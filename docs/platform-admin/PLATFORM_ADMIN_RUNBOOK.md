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

## Phase 2: support sessions, console and review queue

**Looking into a school (support):** Platform home -> Schools -> the school -> *Start support session*. Give a real reason
(shown to the school and kept in the audit log), optional ticket, and a duration. You then see that school's normal screens,
read-only, under a banner; *End session* revokes the grant. Support access never includes uploaded files (admission documents,
photos). After a page reload use *Resume* on the platform home. Roles: OWNER and SUPPORT may start sessions; VIEWER and COMPLIANCE
can only read the directory and overview.

**The school's view:** Settings -> Support access lists who has access now (with the reason and end time), the history, and an
*End access* button. Tell school admins this page exists when you onboard them.

**Deletion requests (Google Play):** Platform home -> Deletion requests (OWNER/COMPLIANCE). Approve only after checking the
reason shown; approving cannot be undone once the processor runs. The processor itself stays OFF until
`ACCOUNT_DELETION_PROCESSING_ENABLED=true` for the project.

**Audit log:** Platform home -> Audit log (OWNER/COMPLIANCE): newest 200 actions, searchable, *Copy CSV*.

**Deploy order for Phase 2** (the rules are stricter: do not deploy them before the app and functions):
1. `firebase deploy --only functions --force --project <p>` (new callables: `requestSupportAccess`, `revokeSupportAccess`,
   `getSchoolOverview`, `listAccountDeletionRequests`; review/process now need OWNER or COMPLIANCE).
2. Hosting.
3. Rules last: `tool/deploy_rules.sh <p> --dry-run`, then `tool/deploy_rules.sh <p>`.
   After this a platform admin sees school data ONLY through a support session; the old blanket access ends.
No new indexes are needed.

## Phases 3 and 4: operating the platform

**Suspending a school:** Schools -> the school -> *Access* -> *Suspend school* (owner). Give a real reason. Everyone at that school
(staff and parents) is paused within seconds; their data stays. *Reactivate school* lifts it. If anything looks inconsistent use
*Re-apply to all users* (owner or support); it is safe to repeat. A school being offboarded cannot be reactivated until the
offboarding is cancelled.

**Creating a school:** Schools -> *Create school* (owner). Country sets currency, time zone and date format. The first administrator
is emailed a link to choose a password. If the email fails, open the school and use *Reset access*.

**Modules:** Schools -> the school -> *Modules* (owner) switches admission management and the public admission page. Existing schools
stay on until you switch them off.

**Billing:** Schools -> the school -> *Billing* -> *Add billing record* (owner). Mark paid with the date it was paid, or waive/void.
Platform home -> Billing shows everything owed per currency. Nothing is collected online.

**Offboarding:** Start it with a reason (suspends the school); a *different* owner approves; *Cancel offboarding* undoes it. It
deletes nothing: the data purge is a separate, manual, rehearsed procedure.

**Notices:** Platform home -> Notices to schools. Everyone or named schools, severity, shown 1-30 days. School and branch admins see
it as a banner and can dismiss it for the session. Withdraw ends it at once.

**Maintenance and forced update:** Platform home -> App availability (owner). See `MONITORING.md` for the emergency way out.

**Dashboard:** Platform home. Numbers refresh nightly; *Recompute now* works at most once every 5 minutes. A red "updated" line means
the nightly job is not running.

### Deploy order for Phases 3-4
1. `firebase deploy --only functions --force --project <p>`: new callables, the nightly `platformStatsRollup` schedule and the
   `schoolStatusChanged` trigger (the first deploy needs the Cloud Scheduler API; the CLI enables it). The deploy also changes the
   admission callables and the public admission page.
2. Hosting (screens, paused screen, maintenance gate, notice banner).
3. Rules last (`tool/deploy_rules.sh <p> --dry-run`, then for real): they add the `schoolAccess` check, `platformStats`,
   `schoolUsage`, `platformNotices` and `platformSettings`.
4. Run *Recompute now* once so the dashboard has numbers, and create the Cloud Monitoring alerts (`MONITORING.md`).
No new indexes are needed.
