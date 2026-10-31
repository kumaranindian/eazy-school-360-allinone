# Production blockers and open issues

Audit date 2026-10-31, repository `release/android-prod-prep` at `e4b9016`. Read-only: nothing below was fixed.
Severity: **Blocker** (do not release until closed) · **High** · **Medium** · **Low**.

| ID | Module | Severity | Title |
|---|---|---|---|
| PB-01 | Platform / UI | Blocker | Test suite is red: 6 branding-header tests fail at phone width |
| PB-02 | Operations | Blocker | No evidence of backup, point-in-time recovery or a restore drill |
| PB-03 | Compliance | Blocker | No privacy policy link anywhere in the app, web or listing assets |
| PB-04 | Verification | High | No end-to-end or load testing; production workflows unverified |
| PB-05 | Students | High | Re-uploading a student sheet creates duplicate students |
| PB-06 | Security | High | App Check is not enforced on the deployed (prod) callables |
| PB-07 | Deployment | High | Deployed prod state cannot be shown to match the repository |
| PB-08 | Account deletion | High | Deletion processor is off and has never run on real data |
| PB-09 | Dependencies | Medium | Functions dependencies: 1 high, 10 moderate advisories |
| PB-10 | Storage | Medium | Photos readable by every user in a branch, including parents |
| PB-11 | Product scope | Medium | Required capabilities absent: late fees, instalments, online payment, promotion |
| PB-12 | Web | Medium | Content-Security-Policy is Report-Only |
| PB-13 | Security | Low | Self-service school creation has no abuse control |
| PB-14 | Auth | Low | No idle-session timeout; mustChangePassword is not enforced by rules |
| PB-15 | Performance | Low | One counter document per branch limits invoice/receipt numbering throughput |
| PB-16 | Documentation | Low | Repository docs are stale about prod Cloud Functions |

---

## PB-01 Test suite is red: branding header at phone width
- **Module:** Platform shell / Help. **Severity:** Blocker (a mandatory gate is "critical automated tests passing").
- **Description:** `flutter test` ends `+1659 -6`. All six failures are `test/widget/branding_shell_test.dart` "<role>: every role gets the same branding header".
- **Reproduction:** `flutter test test/widget/branding_shell_test.dart`.
- **Actual:** `Expected: a numeric value within <20> of <195.0>  Actual: <123.0>` (test line 132): at 390 px width the header title is 72 px off-centre.
- **Expected:** title centred in the bar, as before.
- **Roles affected:** every role on a phone.
- **Source files:** `lib/core/routing/app_shell.dart` (actions: bell + new `ContextualHelpButton` + sign-out), `lib/features/help/presentation/widgets/contextual_help_button.dart`, `test/widget/branding_shell_test.dart`.
- **Attribution:** the extra always-visible Help button was added in the Help work (`e4b9016` and the preceding change); the failing test predates it. Not proven by reverting, because this audit does not change code.
- **Recommended fix:** keep the title centred regardless of action count (reserve symmetric space), or move Help into an overflow menu on narrow widths; then run the full suite before every commit.
- **Validation:** `flutter test` fully green; manual check at 360, 390 and 820 px.

## PB-02 No backup, PITR or restore drill
- **Module:** Operations. **Severity:** Blocker.
- **Description:** the only evidence is a checklist line (`docs/production-audit/DEPLOYMENT_CHECKLIST.md:13`: "PITR enabled; backup taken now; last restore drill < 90 days"). No script, configuration or record shows it is done.
- **Actual:** unverified; this audit could not read project settings without changing anything.
- **Expected:** PITR enabled on the prod Firestore database, scheduled backups, a documented and rehearsed restore, and a stated retention.
- **Roles affected:** all (data loss).
- **Recommended fix:** enable PITR and scheduled backups on `eazy-school-360-prod`; run one restore into a scratch project; write the runbook.
- **Validation:** screenshot/CLI output of PITR enabled, a successful restore log, runbook committed.

## PB-03 No privacy policy
- **Module:** Compliance (Google Play). **Severity:** Blocker for a Play release.
- **Description:** a search of `lib/`, `web/`, `android/` and `docs/` finds no privacy-policy page or URL (only deletion documentation). Play requires a policy URL and a Data safety form for an app that stores children's data.
- **Roles affected:** all; also the school as data controller.
- **Recommended fix:** publish a policy (covering student, parent, financial and photo data, retention and deletion), link it from the sign-in screen and the store listing.
- **Validation:** URL reachable without sign-in; linked in the app; Data safety form consistent with `docs/account-deletion-data-matrix.md`.

## PB-04 No end-to-end or load testing
- **Module:** Verification. **Severity:** High.
- **Description:** there is no `integration_test/` directory and no browser or device test. Workflows are covered by widget tests with fakes, write-plan contract fixtures replayed against real rules (6 contract suites) and unit tests. No load test exists.
- **Actual:** the five business workflows were never run as one flow in a running app against an emulator or dev project in this audit (see `WORKFLOW_AUDIT.md`).
- **Recommended fix:** a scripted smoke run per workflow A-E against the dev project (or emulators) and one load rehearsal with realistic volumes.
- **Validation:** recorded run of each workflow with pass/fail per step.

## PB-05 Sheet re-upload creates duplicates
- **Module:** Students. **Severity:** High (data integrity).
- **Description:** admission numbers are now assigned automatically for sheet uploads (commit `fe77cac`), so the sheet no longer carries an identifier that would reject a second upload of the same file.
- **Reproduction:** import a valid sheet; import the same file again.
- **Actual:** every student is admitted again with a new number. The UI warns about it in text only.
- **Expected:** a second import is refused or flags the rows as probable duplicates.
- **Roles affected:** administrators; every parent/fee record created from the duplicates.
- **Source files:** `lib/features/students/data/bulk_student_importer.dart`, `lib/features/students/domain/bulk_student_import.dart`, `lib/features/students/presentation/pages/student_bulk_import_page.dart`.
- **Recommended fix:** at preview time flag rows whose name + date of birth + class already exist in the branch (or a file-hash guard), and make admission-time duplicate warnings available in the single form too.
- **Validation:** importer test that a second run reports every row as duplicate.

## PB-06 App Check not enforced
- **Module:** Cloud Functions security. **Severity:** High.
- **Evidence:** `functions/call_options.js` enforces only when `ENFORCE_APP_CHECK=true`; the deployed `provisionLogins` on both `eazy-school-360-dev` and `-prod` lists environment variables without `ENFORCE_APP_CHECK` (read via `firebase functions:list --json`).
- **Actual:** any client with a valid Firebase ID token can call every callable. The two public callables (`requestAccountDeletionPublic`, `getDeletionRequestStatus`) and the OTP callables rely on per-email/IP/phone counters (`account_deletion.js:77-78`, `otp.js:18-22`), whose IP comes from request headers.
- **Recommended fix:** ship App Check in the Android and web builds (`APP_CHECK_ENABLED`, `APP_CHECK_WEB_KEY`), then set `ENFORCE_APP_CHECK=true` on prod.
- **Validation:** an un-attested call to a callable is rejected on prod.

## PB-07 Deployed prod state is unverified against the repository
- **Module:** Deployment. **Severity:** High.
- **Evidence:** all 43 functions exist on both dev and prod (40 exports plus three currency-lock triggers), but their source hashes differ (`provisionLogins`: `4c94ce…` on dev, `9e67a7…` on prod). Deployed Firestore/Storage rules cannot be diffed against the repo without a deploy; whether prod Storage is initialised was not provable read-only.
- **Recommended fix:** run `tool/deploy_rules.sh eazy-school-360-prod --dry-run` and a `functions` dry-run, then redeploy prod from `HEAD` in the documented order; confirm Auth providers, authorized domains and the Storage bucket.
- **Validation:** prod functions hash equals dev; rules suite passes against the deployed rules.

## PB-08 Account deletion is not operational
- **Module:** Compliance. **Severity:** High for Play release.
- **Evidence:** `ACCOUNT_DELETION_PROCESSING_ENABLED` is not set on deployed functions (default false); `CLAUDE.md` says the processor "has never run on real data"; the public web form needs Auth email-link and authorized-domain settings that are recorded as not set.
- **Recommended fix:** sign off `docs/account-deletion-data-matrix.md`, rehearse the processor on dev data, enable on prod.
- **Validation:** a test account's request reaches COMPLETED and its data is gone as the matrix states.

## PB-09 Functions dependency advisories
- **Evidence:** `npm audit --omit=dev` in `functions/`: 1 high (`body-parser` DoS via trailing bytes after a compressed body, GHSA-27r3-jxmh-p828; fix available), 10 moderate (chain through `firebase-admin` / `@google-cloud/*`). The Dart OSV scan reports 0 advisories on 137 hosted packages. CI only fails on `critical`.
- **Recommended fix:** `npm audit fix` for the high; schedule the major bumps; lower the CI threshold to `high`.

## PB-10 Photos readable across a branch
- **Evidence:** `storage.rules:103-130`: student, parent and staff photo paths allow read when `isSameBranch()`. `roleIn(branchId)` (`storage.rules:50-56`) returns the caller's role for their own branch, which is `PARENT` for a parent, so any parent in the branch passes. The path needs a student/parent id, which is a random Firestore id, so exploitation needs the id; the download URLs stored in Firestore (`photoUrl`) are token links that bypass these rules entirely.
- **Roles affected:** parents (can read other children's/parents' photos if an id leaks); children's privacy.
- **Recommended fix:** restrict student and parent photo reads to staff of the branch and the linked parent; do not store long-lived token URLs for children.
- **Validation:** rules test where a parent of student A is denied student B's photo.

## PB-11 Required capabilities not present
Late fees, instalments, online payment, year-end promotion, a student report, a finance dashboard and WhatsApp/email/SMS notifications do not exist (`FEATURE_AUDIT_MATRIX.md`). Not defects of existing code; they decide whether the product meets the pilot school's brief.

## PB-12 CSP is Report-Only
`firebase.json` sets `Content-Security-Policy-Report-Only`; nothing is enforced (`FIX_TRACKER` CFG-4). Switch to enforcing after reviewing reports; keep the other headers (HSTS, X-Frame-Options, nosniff).

## PB-13 Open school creation
The users rule allows any signed-in person to create a new school and become its admin (`firestore.rules:1689-1695`). By design for a SaaS, but there is no abuse control (verification, rate limit, approval).

## PB-14 Sessions and forced password change
No idle timeout or forced re-authentication exists in `lib/features/authentication`. `mustChangePassword` is enforced by the router and the callable only; rules do not block a user who ignores the screen (documented in `CLAUDE.md`).

## PB-15 Numbering throughput
Invoice and receipt numbers come from one counter document per branch updated in a transaction (`feeCounters`). Throughput is about one issue per second per branch under contention; bulk invoice generation is sequential. Acceptable for pilot sizes (`FIX_TRACKER` OPS-4 deferred).

## PB-16 Stale documentation
`docs/android-release.md:75` and the "Open items" line in `CLAUDE.md` say prod is not on Blaze and functions cannot deploy. `firebase functions:list` shows all functions deployed on prod. Update the docs so the next release checklist is accurate.
