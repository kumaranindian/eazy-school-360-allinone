# Security & privacy audit

Scope: Firebase Auth, Firestore & Storage rules, Cloud Functions, secrets, privacy, dependencies, hosting. Scans actually executed are listed in TEST_RESULTS.md. Anything only visible in a cloud console is marked UNKNOWN.

## Summary
No P0. Tenant isolation, role escalation and parent/teacher scoping are **enforced by rules and tested** (437 emulator tests pass on `develop`). The blocking concerns are *delivery* and *operations*: the rules may not be deployable (SEC-1), App Check is off, and push/device hygiene leaks pushes to the wrong person on shared devices.

## Authentication & session
* Sign-in methods gated per user and per school by `users.login` (server-written) and checked in rules + functions; disabled logins are refused on every read/write even with a valid ID token (rules `activeAndAllowed`). ✔
* Session revocation: `revokeRefreshTokens` is used for "sign out all devices"; rules do not check token age, so an unexpired ID token of a *status-disabled* user is refused (status check) but **push registration is not revoked** (NOTIF-1/2).
* Duplicate accounts: email-in-use handling in provisioning and the cross-branch mapping (school-admin only) ✔.
* Brute force: OTP has per-phone/IP limits (`otp.js`); IP source behind Cloud Run UNKNOWN; lock-out/DoS of a victim's number possible (SEC-3). Password sign-in relies on Firebase Auth's own throttling.
* App Check: opt-in, **off** (SEC-2).
* Router: every non-public path needs a signed-in user and resolved tenant; `/students/import`, `/staff/import`, `/settings/academic-years/school` are not in `requiredPermissions` (ROUTE-1) but are guarded in-page and by rules.

## Authorization & tenant isolation (rules)
* Default-deny at `firestore.rules` (`match /{document=**}`) and `storage.rules`; no `allow … if true`; no collection used by the app lacks a rule (script check: only `noticeReads`/`preferences`, which are matched under `users/{uid}`).
* `/users`: self-update limited to name/phone/photo; `role`, `schoolId`, `email`, `login`, `branchRoles` not client-writable (create blocks `login` and `branchRoles`; update uses `changedOnly`). ✔ (tests in `login-access-rules`, `multi-branch-rules`)
* Per-branch roles: `branchRoleOf` accepts only BRANCH_ADMIN/TEACHER/FINANCE from `branchRoles`; corrupt values (e.g. `SCHOOL_ADMIN`) grant nothing (tested). ✔
* Parents: scoped by `linkedParentId` + `parentAccess` (classes/sections of ACTIVE portal-enabled children); notices/announcements by audience pinned queries. Teachers: `teacherAccess` sections. Both fail closed on missing index docs. ✔
* Collection-group exposure: `parentLinks`, `academicRecords` have explicit CG rules requiring tenant fields. ✔ (tests)
* **Rule size** (SEC-1): 223,727 B; live state UNKNOWN.
* **Attendance** (ACAD-9): rules cannot confirm the student's enrolment; a crafted write by a class teacher can reserve another student's day-record.
* Leave day-locks and scheduled-announcement visibility are client-enforced (ACAD-10, ACAD-6).
* Self-signup lets any signed-in user create a school (no email-verified/App Check gate) — spam tenants (SEC-6).

## Cloud Functions
* Callables check `request.auth`, then the caller's role/school in the user profile (`assertAdmin`/`assertSchoolAdmin`), cap batch sizes (`provisionLogins` ≤ 50), never take uid/school from the payload for device registration (`devices.js`). Secrets via Secret Manager. ✔
* `feeDueReminders` global scan (SEC-4); no explicit timeout/memory (NOTIF-3); `refreshMyParentAccess` has no rate limit (P3).

## Privacy & logging
* **LOG-1:** email address and a student's name reach Crashlytics via `AppLogger.error` → `errorSink`.
* **LOG-2:** raw `debugPrint` of callable error bodies and probe identifiers remains in release builds.
* Push payloads carry only `refType/refId/branchId/source/schoolId` as data; title/body are visible on the lock screen (Android `visibility: public`); absent-child alerts include the date (NOTIF-6).
* Student photos/documents: Storage rules limit by role/branch; SVG allowed in image uploads (SEC-6); no malware scan on homework uploads.
* Firestore persistence is not cleared at sign-out (STATE-7, UNKNOWN on device).

## Secrets
Pattern scan of the tree found **no** private keys, service-account JSON, keystores, tokens or `.env` files. The only `AIza…` strings are public Firebase client keys in `firebase_options_{dev,prod}.dart` and `config/firebase/**` (public by design; HTTP-referrer/app restrictions in Google Cloud are UNKNOWN). `.gitignore` covers `key.properties`, `*.jks`, `*.keystore`, `.env*`; add `*.p8 *.p12 *.pem *.mobileprovision serviceAccount*.json` (CFG-9). Git-history scanning with a dedicated tool was **NOT RUN** (no gitleaks/trufflehog installed).

## Dependencies
* Dart: `tool/osv_scan_pub.py` **could not run** (sandbox proxy returned 403) — last successful result per the M12A doc: 0 advisories in 125 packages; current lockfile has 139 entries, so **re-run in CI/online**.
* `functions`: `npm audit --omit=dev` → 9 vulnerabilities (2 high: `node-forge` via `firebase-admin@12`, 7 moderate incl. `uuid`) (DEP-1).
* `firestore-tests` (dev only): 5 high in the emulator test harness; not shipped.

## Hosting / transport
HSTS, `nosniff`, `X-Frame-Options: DENY`, referrer & permissions policies present; **no CSP** (CFG-4); `storage.cors.json` allows `*` for GET/HEAD if applied (CFG-5, UNKNOWN whether applied).

## Audit trail
Present: financial events (in-transaction audit), `authAudit`, `branchAccessAudit`, `studentTransfers`, announcement/homework/exam histories, leave ledger. Missing or best-effort: invoice-generation audit entry is swallowed on failure by design; no audit for role changes made directly in `users` by school admins (only the server-written ones).

## Backups & retention
No backup, PITR, retention or restore-access configuration is in the repo (OPS-1). UNKNOWN — REQUIRES VERIFICATION.
