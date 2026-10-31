# Security audit

Audit date 2026-10-31 · `release/android-prod-prep` @ `e4b9016` · read-only. Evidence is repository code, test output and read-only Firebase CLI listings. **No live cross-tenant probing was done against dev or prod**, and the rules actually deployed to prod could not be read back (see PB-07).

## Result in one paragraph
No critical vulnerability was found. Tenant isolation, role boundaries and the financial write path are enforced in Firestore rules and are backed by 479 passing emulator tests, run serially against the *built* (deployable) rules. The weaknesses are operational and defence-in-depth: App Check is off on the deployed functions, Storage photo reads are broader than needed, dependency advisories exist in Functions, and deployed prod state is not provably equal to the repository.

## Test evidence
| Check | Result |
|---|---|
| Firestore + Storage rules suite, serial, built artifact (`RULES_FILE=../build/rules/...`) | 479 / 479 pass |
| Rules build size gate (`tool/build_rules.js --check`) | firestore 149 KB (56.9 % of limit), storage 9.9 KB |
| Cloud Functions unit tests | 251 tests: 250 pass, 1 skipped, 0 fail |
| Deletion processor on Firestore + Auth emulators | 1 / 1 pass |
| Repository tooling tests (indexes, CSP, signing, manifest, rules build) | 24 / 24 pass |
| OSV scan of Dart packages | 137 hosted packages, 0 advisories |
| `npm audit --omit=dev` (functions) | 1 high, 10 moderate, 0 critical |
| Secret scan of tracked files (private keys, service accounts, live tokens) | none found; `key.properties`, keystores, `.env*`, service accounts are git-ignored |

## Authentication
- Sign-in is Firebase Auth (email/password, Google). Phone OTP exists but is switched off on both projects: the deployed `provisionLogins` environment shows `META_WA_PHONE_NUMBER_ID` and `META_WA_TEMPLATE_NAME` empty.
- Identity maps to `/users/{uid}`; every rule calls `isActiveCaller()` (profile exists, `status == ACTIVE`, `loginAllowed()` which honours the per-user `login` object and the per-school allowed methods; Google additionally requires a verified email equal to the profile email). A disabled user is therefore cut off server-side on the next request even with a valid token (`firestore.rules` ~L1676-1736; `storage.rules:14-40`).
- Findings: no idle-session timeout; `mustChangePassword` is app-enforced only (PB-14). Self-service school creation has no abuse control (PB-13).

## Authorization and Firestore rules
- **Default deny:** the file states "no `allow read, write: if true`", and a search confirms none; Storage ends with `allow read, write: if false` (`storage.rules:311`).
- **Tenant scoping:** data lives under `schools/{s}/branches/{b}/...`. Writes call `newInTenant()` (schoolId/branchId equal to the path). Of 84 `update`/`write` rules, 42 contain no field-restriction helper in the same statement; each of those is `if false` (server-only or append-only history, counters, audit logs) except nine, which I read individually and each pins `schoolId`/`branchId`/ownership fields: `leaveTypes`, `periodSets`, `gradingSchemes`, `examRemarks`, plus `homeworkSubmissions`, `announcements`, `examinations`, `marksSheets` and `conversations` via dedicated validators.
- **Privilege escalation:** the `users` rule limits who may create or change which roles: school admins manage `BRANCH_ADMIN/TEACHER/FINANCE/PARENT`; branch admins manage `TEACHER/FINANCE/PARENT`; self-update is limited to name/phone/photo; `role`, `schoolId`, `status`, `email` and `login` cannot be changed by the user, and `login`/`branchRoles` cannot be set on create (`firestore.rules:1676-1736`).
- **Server-written access indexes:** `teacherAccess/{uid}` and `parentAccess` are what scope teachers and parents to sections/children. `teacherAccess` is `allow write: if false` (Cloud Functions only), so teacher access depends on the deployed triggers (they are deployed on dev and prod).
- **Rules cost:** each request resolves the caller profile with `get()`; Firestore bills these as reads and caps lookups per request (the team already restructured rules around the 1000-expression and size limits). Not a vulnerability; see `PERFORMANCE_AUDIT.md`.

### Financial integrity (verified in rules)
`payments` create requires: staff of the fee role, `createdBy == auth.uid`, tenant match, positive integer minor units, allowed method (reference number for non-cash), an existing `ISSUED`/`PARTIALLY_PAID` invoice for the same student and year, `amount <= balance`, `balanceAfter == balance - amount`, the invoice moved by this payment in the same commit, and a matching receipt created in the same commit (`firestore.rules:2654-2678`). The document id is the idempotency key. A payment can only change `ACTIVE -> REVERSED` with a reversal record and the invoice giving the money back in the same commit; delete is denied. Findings: the payment date is a client-supplied string (back-dating is possible by fee staff, an audit-trail matter, not an escalation).

## Tenant isolation
- **Test coverage:** `tenant-sweep*.test.mjs` discover collections automatically; `rbac-screen-sweep`, `rbac-first-load`, `no-profile-denied`, `multi-branch-*`, `parent-scope` exercise cross-school, cross-branch and cross-role reads/writes. All pass.
- **Not done:** an adversarial live attempt against the deployed dev/prod projects with two real schools. Cross-tenant safety is therefore *verified in the emulator against repository rules*, not on the deployed rules.

## Storage
- Defaults to deny; per-path rules require same school/branch; uploads have size and content-type limits (images <= 2 MB at school level; homework, announcements, conversations use signature/type policies mirrored in `AnnouncementFilePolicy` etc.); most paths forbid delete; creates are create-only (`resource == null`).
- **Finding PB-10 (Medium):** student, parent and staff photo reads use `isSameBranch()`, which is true for a parent in that branch. Practical exploitation needs a random document id; the stored `photoUrl` download URLs are bearer tokens that bypass rules anyway (uploaders call `getDownloadURL()` for school, student, parent and staff photos).
- No malware scanning of uploads; SVG is excluded by the content-type checks.

## Cloud Functions
- 40 exports (43 deployed with three currency-lock triggers). Every callable except four starts with `signedIn(request)` or `request.auth`; the four exceptions are intentionally public: `requestPhoneOtp`, `verifyPhoneOtp` (phone sign-in) and `requestAccountDeletionPublic`, `getDeletionRequestStatus` (web form). The public ones have counters: deletion 3 per email / 10 per IP (`account_deletion.js:77-78`); OTP 5 per phone / 20 per IP, 5 attempts per code (`otp.js:18-22`).
- Admin callables check the caller's role and tenant on the server (`provision.js`, `access.js`, `branch_access.js`); `reviewAccountDeletion`/`processAccountDeletion` require an active `PLATFORM_ADMIN`.
- Secrets use Secret Manager (`META_WA_ACCESS_TOKEN`, `OTP_PEPPER`); passwords are never stored or logged (the log line carries only ids and flags).
- Idempotency: push fan-out claims per delivery (`pushDeliveries`) with a redrive sweep; payments and invoices use deterministic ids.
- **Finding PB-06 (High):** `ENFORCE_APP_CHECK` is not set on deployed functions, so the abuse controls above are the only barrier for the public callables and the IP value is taken from request headers.
- `maxInstances: 10` is set globally; region `asia-south1` matches Firestore.

## Data exposure
- Logging: `LOG-1` redaction exists (emails masked under `AUTH_TRACE`); function logs avoid emails and passwords.
- Web: headers set (HSTS, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy); CSP is Report-Only (PB-12).
- Firebase client config files for dev and prod are committed. That is normal for Firebase client keys; their security rests on rules and App Check, which is why PB-06 matters.

## Recommended remediation (ordered)
1. Enforce App Check on prod (PB-06) and restrict the web API key to the production domain.
2. Redeploy prod from `HEAD` after dry-runs and confirm deployed rules by re-running the rules suite against the project's emulator-exported rules (PB-07).
3. Narrow student/parent photo reads and stop persisting token URLs for minors (PB-10).
4. Fix the high `body-parser` advisory and lower the CI audit threshold to `high` (PB-09).
5. Switch CSP to enforcing (PB-12); add idle timeout and rules-level enforcement of password change if the school policy requires it (PB-14).
6. Add abuse control to school self-registration (PB-13).
