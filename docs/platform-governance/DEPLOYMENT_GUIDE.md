# Deployment guide: school lifecycle, subscriptions, feature control and audit

**Nothing in this guide has been run.** No Firebase project (dev or prod) was touched while building this. Every step below is for a person to run
after approving it. Production needs its own explicit approval; follow the same order there only after dev has been verified.

## 0. What is being released
| Piece | New / changed |
|---|---|
| Cloud Functions | about 50 new functions (callables for lifecycle, recovery, subscriptions, features, notifications, audit; triggers `schoolCreated` (changed), `moduleWatch_*` (20), `auditMirrorPlatform`, `auditMirrorAuth`; schedulers `subscriptionMonitor` (15 min), `auditRetention` (daily)). 159 functions in total (109 callable, 41 event, 9 scheduled). |
| Firestore indexes | 6 composite indexes on `events` (audit trail). They take time to build. |
| Firestore rules | **one line**: a client-created school must be `INACTIVE` (decision D1). Compiled size +2 bytes; margin is thin. |
| Storage rules | unchanged |
| App (web, Android, iOS) | per-state "account paused" screens, the console (activation, subscriptions, modules, audit trail), the notification popup and inbox, module switches that hide features, self-registration creates INACTIVE schools |
| Data | additive only. No backfill is required (see the dry run). New collections have no client rules. |

## 1. Before anything is deployed (local, no approval needed)
```
flutter analyze && dart format --output=none --set-exit-if-changed . && flutter test
(cd functions && npm test)                       # includes index_exports and deploy_manifest (what Firebase will see)
node --test "tool/*.test.js" && node tool/build_rules.js --check
firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && npm test"
RULES_FILE=../build/rules/firestore.rules STORAGE_RULES_FILE=../build/rules/storage.rules \
  firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && npm test"
```
Expected today: Flutter 2,471, functions 691 pass (1 skipped), tools 40, rules 564 of 565 (the one failure, `admission-storage-rules` #36, predates this work: see READINESS_ASSESSMENT.md).

## 2. Read-only dry run against the target project (needs credentials and your approval to read that project)
```
node tool/governance_dry_run.js --project eazy-school-360-dev
node tool/governance_dry_run.js --project eazy-school-360-prod --read-prod     # only when approved
```
It writes nothing (the database handle refuses every write; a test proves it). It reports: schools by state, schools without a recognised status
(treated as ACTIVE), schools without a time zone, unknown/inconsistent module switches, subscriptions that would pause an ACTIVE school within
15 minutes of deploy, users whose pause mirror is wrong, and which new collections already exist. Exit code 0 = nothing needs a decision, 1 = review the ATTENTION lines.
**Expected for a project with no subscriptions: nothing blocked, no data change.**

## 3. Order of deployment (dev first)
1. **Back up**: export Firestore (`gcloud firestore export gs://<backup-bucket>/pre-governance-<date> --project <id>`) or use the console's managed backups. Note the time.
2. **App availability (decision D1)**: in the platform console, set the minimum build to the new release BEFORE the rules change, so an old app cannot try to self-register an ACTIVE school (it would be refused halfway through sign-up).
3. **Indexes**: `firebase deploy --only firestore:indexes --project <id>`; wait until every new `events` index shows READY (console > Firestore > Indexes). The audit trail page errors until they are ready.
4. **Functions**: configure `functions/.env.<id>` from `functions/env.example` (the three new settings have safe defaults), then `firebase deploy --only functions --project <id>`.
   Enable the Cloud Scheduler API first if it is not enabled. The first deploy creates ~50 functions: expect it to take a while and check the project's function quota (default 1,000 per region).
5. **Smoke test on the deployed functions** (section 4).
6. **Hosting (web)**: build with `flutter build web --release -t lib/main_dev.dart --dart-define=APP_ENV=dev` and deploy hosting.
7. **Rules last**: `tool/deploy_rules.sh <id> --dry-run`, then for real. Measure with a REAL dev release (the compiled size is only knowable that way); keep >= 1 KB headroom. If it is refused with 409, run `firebase deploy --debug` to read the real message.
8. **Mobile**: build and publish the Android/iOS releases (version number must increase). Until users update, old apps keep working against the new server except self-registration (see 2).
Never use `firebase deploy` without `--only`, and never `--only firestore:rules` with the default config (see CLAUDE.md).

## 4. Smoke test on dev (about 20 minutes, platform owner with two-step verification)
Prerequisite: the dev project must have **MFA enabled** (it is not today: enable it in the Identity Platform settings first) and a platform owner created with `tool/create_platform_admin.js`.
| # | Do | Expect |
|---|---|---|
| 1 | Create a school in the console | it appears INACTIVE; its administrator can sign in and sees "Account is inactive. Please contact admin@avail404.com." |
| 2 | Activate it with remarks and a message | status ACTIVE; the administrator gets a popup with the message and must press "I understand"; the history shows the change |
| 3 | Self-register a new school in the app | it lands on the inactive screen; the console lists it under Inactive |
| 4 | Suspend it with a reason, then reactivate | everyone is paused within seconds, then restored; the reason is NOT shown to the school |
| 5 | Grant a 14-day trial; then set an end date in the past | status TRIAL; with an ended subscription the school becomes EXPIRED within 15 minutes (or immediately via Renew/Cancel) and renewing restores it |
| 6 | Switch the Fees module off (confirm dependants) | Fees disappears from the school's navigation and `/fees` is refused; history shows two rows; the admin gets a dismissible notice |
| 7 | Create a student in a school with Students switched off (use a direct client write) | a `FEATURE_ACCESS_DENIED` event appears in the audit trail; the record is NOT removed |
| 8 | Open Audit trail, filter by school and by "Denied", export CSV | events listed newest first, "reported by the app" badges only where applicable; the export itself is listed as `AUDIT_LOG_EXPORTED` |
| 9 | As a SUPPORT role user open the Audit trail | refused |
| 10 | Wait 15 minutes | `subscriptionMonitor` ran (Cloud Functions logs: "subscription monitor", failed 0) |
| 11 | Run the dry-run script again | no new ATTENTION lines |
Roll back immediately (section 5) if step 1, 4 or 5 does not behave as written.

## 5. Rollback
| Step | How | Data effect |
|---|---|---|
| Functions | redeploy the previous commit's functions (`git checkout <previous> -- functions` in a scratch worktree, never on top of uncommitted work) | none. Older code ignores new fields and collections; lifecycle states it does not know (EXPIRED/CLOSED/INACTIVE) read as "paused", so rollback keeps users paused rather than unlocking anyone |
| Indexes | leave them (harmless); delete only if cost matters | none |
| Rules | `tool/deploy_rules.sh <id>` with the previous `firestore.rules` | schools created INACTIVE stay INACTIVE (an owner can activate them) |
| Hosting | redeploy the previous build | none |
| Emergency switch for subscriptions | set `GOV_SUBSCRIPTION_ENFORCEMENT=false` in `functions/.env.<id>` and redeploy functions | subscription checks stop; the scheduler still records status but no school is blocked by a subscription; lifecycle (suspend/inactive/closed) is unaffected |
| Audit | nothing to roll back; the trail is append-only and retention deletes nothing unless `AUDIT_RETENTION_DELETE=true` | none |
Schools the scheduler already moved to EXPIRED stay EXPIRED after a rollback; renew their subscription (or activate them from the console) once the new code is back.

## 6. After a successful dev run
Re-read READINESS_ASSESSMENT.md, decide the open items there, and ask for approval before repeating sections 2-8 on production. A production release also needs the Play/App Store builds, a monitoring alert on the new schedulers and the trigger retry rate (docs/platform-admin/MONITORING.md), and the retention decision (D9).
