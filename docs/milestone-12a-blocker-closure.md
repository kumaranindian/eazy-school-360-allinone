# Milestone 12A — Production Blocker Closure

Continues `docs/milestone-12-production-readiness.md` (not restarted). Every
finding below was re-checked against the current source before work began.

**Revised release recommendation: NOT READY FOR RELEASE — but the remaining
blockers are now all owner/operations actions; none is a known code defect.**
Staging can be stood up as soon as §9 steps 1–4 are done.

Nothing was deployed, no production configuration or signing credential was
created or changed, and no live data was written. Financial schema and write
paths are untouched.

## 1. Summary by finding

| ID | Sev | State after 12A | Release impact |
|---|---|---|---|
| F-SEC-3 | P2 | **Fixed in code and rules** (class/section least privilege; school-wide announcements preserved). Needs a one-time *Refresh parent access* per branch at cutover. | Closed once deployed in the documented order |
| F-FIN-1 | P2 | **Assessed**; architecture, threat model and phased plan written. No migration (needs approval). | Accepted limitation for a pilot; required before online payments or multi-school scale |
| F-DEP-1 | P2 | **Scan method found and run**: 0 advisories in 125 Dart packages; 5 high in npm test tooling (not shipped). CI step added. | None for shipped code |
| F-OPS-1 | P2 | **Validated locally**; found and fixed two defects that would have failed CI. Execution on a real runner remains. | Low |
| F-OPS-2 | P2 | **Validated locally** with the hosting emulator (headers, deep links, cache). Production domain checks remain. | Low |
| F-DATA-1 | P2 | **Exact procedure documented** (§7); nothing enabled or rehearsed (needs the project). | Blocker until enabled + rehearsed |
| F-REL-1 | P1 | **Setup path fixed** (per-platform options; the old instructions would have broken the build). Needs the owner's projects. | **Blocker** |
| F-REL-2 | P1 | Signing hook in place; owner supplies keystore (§9). | **Blocker** for store builds |
| F-REL-3 (new) | P1 | Firebase options model could not serve web+Android+iOS from one object, and the setup note would have replaced the constant the app imports. **Fixed.** | Removed |
| F-OPS-3 (new) | P1 | The four option files were git-ignored, so a clean checkout (CI) could not compile. **Fixed** (placeholders committed). | Removed |
| F-SEC-4 (new) | P3 | Class/section-targeted *announcements* are still readable by any family with a child in the same branch (query shape would need a redesign). Documented residual. | Accept or schedule |

## 2. F-SEC-3 — parent access to class-specific content

**Evidence (before).** The M12 sweep showed a parent of branch South could read
North's published homework, announcements, notices, examinations, live
timetable and substitutions, because rules could not tie a parent to a
class/section.

**Policy implemented**

| Content | Who may read (parents) |
|---|---|
| Homework (published/closed) | family with a child in *that class and section* |
| Timetable, live entries, substitutions | family with a child in that class and section |
| Examinations | class-wide exam → child in the class; section exam → child in that section |
| Examination *results* | unchanged: the linked child only (already child-bound) |
| Announcements / notices, audience `ALL` | any parent of the school (legitimately school-wide) |
| Announcements / notices, `BRANCH`, `PARENTS`, `CLASS`, `SECTION` | family with a child in that branch |
| Teachers | unchanged (their branch) |

**Mechanism.** Rules cannot enumerate a parent's children, so a small derived
document `branches/{b}/parentAccess/{parentId}` lists `classKeys` (`classId`)
and `sectionKeys` (`classId__sectionId`) for the family's ACTIVE, placed
children behind an ACTIVE portal-enabled link. Rules do one `get()` of it.
A missing document grants nothing (fail closed).

* Written only by staff who manage student data (rules: tenant/branch/parent
  id pinned, list sizes bounded, `updatedBy == auth.uid`, never deleted).
  Families cannot write it; a family reads only its own.
* Recomputed *from* the student/link documents (never patched) after: link a
  parent, change a link, transfer a student, change a student's status.
  Best-effort: a failure is logged and never fails the business write.
* *Refresh parent access* (Parents list, managers only) recomputes every
  family of the branch — also the backfill for existing data.
* Collection-group `parentLinks` reads were extended to staff who may already
  read the nested link (same visibility), so the refresh can look a parent's
  children up for one branch.

**Client changes (smallest set).** Families' examination list now issues two
queries (class-wide; own section). Homework, timetable and substitution
queries already pinned class/section and are unchanged. New composite index:
`examinations(academicYearId, classId, status, sectionId)`.

**Failure modes (honest).**
* Stale-too-long index (a refresh failed after a transfer/withdrawal) keeps
  old access until the next refresh; stale-too-short withholds content.
  Mitigation: refresh after every relevant write + the admin action + the
  reconciliation note below.
* Mixed versions: old app builds query examinations without `sectionId`; after
  the rules deploy those queries are refused. Deploy the app first.
* F-SEC-4 (above) is not closed by design.

**Cutover (needs approval; not performed).**
1. Deploy the app version containing the two-query exam list and the refresh
   action to staging, then production; wait for adoption of the mobile builds.
2. Deploy the `examinations` index and wait for it to build.
3. **Before** deploying rules: sign in as a branch/school admin, open
   *Parents → Refresh parent access* for every branch. (Rules deployed first
   would hide class content from every family until this runs.)
4. Deploy `firestore.rules`. Smoke-test one family per branch.
5. Rollback: redeploy the previous `firestore.rules`; the index documents are
   inert and harmless.

**Tests.** `parent-scope.test.mjs` (9): homework per section, missing index,
other branch, other school, a parent id that collides across schools,
examinations (class-wide vs section; both query shapes), schedules and
substitutions, announcements (school-wide kept; branch-targeted needs a child
there), index write/read rules and validation, access ending when keys are
removed, branch lookup of links. Existing exam/homework/timetable suites were
updated for the new shapes. `tenant-sweep` no longer allows any parent
exposure except `leaveTypes`. Dart: `ParentAccessKeys` (5). Mutation check of
the new rules: **14 mutants, 14 killed** (two initial survivors exposed real
gaps — index size bound, cross-school id clash — and were closed with tests).

## 3. F-FIN-1 — what needs a trusted backend (assessment only)

**What rules already guarantee (tested, 33 + sweeps).** Per commit: an invoice
moves only with its payment/receipt/reversal; amount ≤ balance; `balanceAfter`
arithmetic; receipt amount equals payment; one invoice per student/period;
invoice and receipt numbers unique and sequence-bound against a counter in the
same commit; payments/receipts immutable; reversal admin-only, once, with a
reason; stale concurrent writers lose; audit log append-only.

**What rules cannot guarantee**

| Threat | Why rules can't stop it | Needs backend? |
|---|---|---|
| T1 A legitimate cashier records a payment that never happened (fraud) | rules cannot know real-world money | Process control + backend maker-checker/alerts; reconciliation |
| T2 Backdated `paymentDateKey` | only format-checked; no trusted "today" for a date key | Server sets the business date |
| T3 Independent totals (day-book, class totals) | no cross-document sums | Server-side aggregation/ledger |
| T4 Gapless statutory numbering under heavy contention | single counter document (≈1 write/s), client retries | Server allocation (sharded or per-register series) |
| T5 Online/gateway payments | signature verification needs a secret | **Mandatory** backend |
| T6 Receipt delivery (email/SMS/PDF archive) | needs secrets/queues | Backend |
| T7 Privileged corrections | admin can reverse; no two-person rule | Backend approval workflow |
| T8 Owner-console edits | outside rules by definition | Audit export + backups |

**Minimal architecture (proposal).** Cloud Functions (2nd gen, callable) with
Admin SDK, region fixed, App Check enforced:

* `issueInvoice`, `recordPayment`, `reversePayment`, `waiveInvoice` — each
  takes the same *plan* the client builds today (`FeePlanners`), re-validates
  caller role/branch from the user profile, re-reads the invoice in a
  transaction, applies the identical writes, allocates numbers inside the
  transaction, and writes the audit entry. Idempotency key = the client's
  payment/event id (already deterministic).
* Rules then **deny client writes** to `payments`, `receipts`, `invoices`
  money fields, `*Numbers`, `feeCounters`, `paymentReversals`, `invoiceWaivers`;
  clients keep read access and real-time streams.
* Secrets (gateway, SMS) live in Secret Manager, never the client.

**Phased, reversible plan (each phase needs your approval).**
0. Build functions + emulator tests that replay the existing contract fixtures;
   no production effect.
1. *Shadow*: functions validate and log what they *would* write; clients still
   write directly; compare daily.
2. *Dual*: new app version calls functions; rules still permit direct writes
   (rollback = old app).
3. *Cutover*: tighten rules; historical documents untouched (no migration —
   the document shapes are unchanged).
4. Remove the client write path after a stable period.

**Recommendation.** For a single-school pilot with named finance staff, accept
rules-only with controls: separate cashier and approver accounts (procedural),
daily reconciliation with `InvoiceReconciler`, reversals admin-only,
backups on. Require the backend before any of: online payments (T5), more
than one school sharing an operations team, statutory gapless numbering at
volume (T4), or an insider-fraud threat model (T1/T7).

## 4. F-DEP-1 — vulnerability scanning

| Method | Command | Result (actual, 2026-10-10) |
|---|---|---|
| OSV database, Dart packages | `python3 tool/osv_scan_pub.py` (stdlib only; reads `pubspec.lock`) | 125 hosted packages checked, **0 advisories** |
| `dart pub audit` | n/a | Not available in Dart 3.8 / Flutter 3.32.8 |
| npm advisories, rules-test tooling | `npm audit` in `firestore-tests` | **5 high**, all transitive via `@firebase/rules-unit-testing → firebase → @grpc/grpc-js` (GHSA-m9gg-hp2v-232j mTLS auth-context, GHSA-f596-whhp-79r4 error-message disclosure) |

The npm findings are in the emulator test harness only; nothing from
`firestore-tests` ships in the app. `npm audit fix --force` proposes a
breaking downgrade, so it was not applied; track a `rules-unit-testing`/`firebase`
upgrade when published. CI now runs the OSV scan (fails on any advisory;
exit 2 = scan could not run = unknown) and `npm audit --audit-level=critical`.
Caveat: OSV only knows *published* advisories.

## 5. F-OPS-1 — CI validation

| Check | How | Result |
|---|---|---|
| Workflow syntax and step shape | Ruby YAML parse + step assertions | valid (2 jobs) |
| Every CI command runs locally | executed individually: format check, analyze, tests, release web build, contract-fixture export, rules suite, OSV scan, `npm audit` | pass (see §8) |
| Clean-checkout reproducibility | `git check-ignore`/`--ignored` review | **defect found and fixed**: the four `firebase_options_*.dart` were git-ignored (clean clone could not compile) — now committed placeholders |
| Runner behaviour | — | **not verifiable here** (no GitHub runner); remaining owner check |

Remaining, environment-dependent: first green run on GitHub; Flutter version
pin `3.32.8` availability in `subosito/flutter-action`; Node 20/Java 21 for
the emulators; secrets none required.

## 6. F-OPS-2 — hosting validation

Served `build/web` with the **Hosting emulator** using the repo's
`firebase.json` and checked responses: security headers present on `/`
(`nosniff`, `X-Frame-Options: DENY`, referrer, permissions, HSTS); a deep
link (`/students/abc`) returns the app shell (SPA rewrite); `flutter_bootstrap.js`,
`index.html`, `/` and extension-less deep links are `no-cache` (a first
attempt left `/` and rewritten deep links cacheable; fixed with explicit
header rules and re-tested). Note: unknown asset paths also return the shell (standard SPA
behaviour; P3). A CSP was **not** added — it needs verification in a real
browser against CanvasKit/font hosts.

Owner checks left: custom domain + managed certificate, HSTS preload decision,
authorised domains in Authentication, header check against the real domain.

## 7. F-DATA-1 — backup / PITR (exact, per environment)

Prerequisites: Blaze plan; `gcloud` authenticated as a project owner;
`<PROJECT_ID>` = the selected environment's real project id (not invented
here); `<LOCATION>` = the Firestore database location shown in the console.
Verify each flag against `gcloud firestore --help` for the installed version
(gcloud was not available in this environment, so **none of these commands
was executed**).

1. **Point-in-time recovery** (7-day window, minute granularity):
   `gcloud firestore databases update --database='(default)' --enable-pitr --project=<PROJECT_ID>`
   Verify: `gcloud firestore databases describe --database='(default)' --project=<PROJECT_ID> --format='value(pointInTimeRecoveryEnablement)'` → `POINT_IN_TIME_RECOVERY_ENABLED`.
2. **Scheduled backups** (longer retention than PITR):
   `gcloud firestore backups schedules create --database='(default)' --recurrence=daily --retention=7d --project=<PROJECT_ID>` and weekly:
   `… --recurrence=weekly --day-of-week=SUNDAY --retention=14w`.
   Verify: `gcloud firestore backups schedules list --database='(default)' --project=<PROJECT_ID>`.
3. **Storage**: enable object versioning and soft delete on the bucket named in
   the environment's options (`<BUCKET>`): `gcloud storage buckets update gs://<BUCKET> --versioning --soft-delete-duration=7d`; add a lifecycle rule deleting
   non-current versions after 30 days.
4. **Access**: restrict `roles/datastore.owner`/backup admin to named owners;
   alert on schedule deletion.

**Restoration drill (run in staging before production; record the result).**
1. Never restore over the live database. Restore to a *new* database:
   backup → `gcloud firestore databases restore --source-backup=projects/<PROJECT_ID>/locations/<LOCATION>/backups/<BACKUP_ID> --destination-database=<SCRATCH_DB>`;
   PITR → `gcloud firestore databases clone --source-database=projects/<PROJECT_ID>/databases/'(default)' --destination-database=<SCRATCH_DB> --snapshot-time=<RFC3339_UTC>`.
2. Verify the scratch copy: per-collection document counts versus the source
   at the snapshot time; run `InvoiceReconciler` over the branch's invoices and
   payments (no `ReconciliationIssue` expected); spot-check one result version,
   one conversation counter, one `parentAccess` document.
3. Copy back only the affected collections, through an audited script, after
   approval; run *Refresh parent access* afterwards.
4. Record: date, backup/snapshot id, duration, discrepancies, approver.

Status: **documented, not enabled, not rehearsed.**

## 8. Verification results (actual)

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 455 files, 0 changed |
| `flutter analyze` | No issues found |
| `flutter test` | **882 passed** (877 at M12; +5 `ParentAccessKeys`) |
| Rules suite, serial | **290 passed** (281 at M12; +9 parent scope), 0 failed |
| Mutation check (F-SEC-3 rules) | 14/14 killed |
| `python3 tool/osv_scan_pub.py` | 125 packages, 0 advisories |
| `npm audit --audit-level=critical` | exit 0 (5 high, dev tooling) |
| Hosting emulator | headers, SPA rewrite, no-cache verified |
| `flutter build web --release` | ✓ built `build/web` |
| `flutter build apk --release` | ✓ 68.1 MB — still **debug-signed** (no keystore) |
| `flutter build appbundle --release` | ✓ 52.4 MB — still **debug-signed** |
| `flutter build ios --release` | blocked: iOS 26.5 platform not installed |

## 9. Owner setup checklist — F-REL-1 and F-REL-2

No project id, credential, domain or key below is invented; angle-bracket
values are yours to supply.

**Firebase projects (F-REL-1)**
1. Decide environments (at minimum *staging* and *prod*; dev/test/uat files
   exist). One Firebase project per environment; never share.
2. For each: create the project; enable Authentication (Email/Password;
   Google if wanted), Firestore (Native mode, chosen location), Storage.
3. Register apps: Web; Android `com.avail404.eazyschool.eazyschool360`; iOS
   `com.avail404.eazyschool.eazyschool360`. Add Android SHA-1/SHA-256 (debug
   for staging, upload + Play app-signing for prod).
4. Authentication → Settings → authorised domains: your hosting domains only;
   remove `localhost` in prod.
5. `flutterfire configure --project=<ID> --out=/tmp/firebase_options_<env>.dart`;
   copy each platform's block into
   `lib/core/config/firebase_options/firebase_options_<env>.dart`
   (instructions are at the top of each file).
6. Deploy rules/indexes/storage to **staging first**; follow §2 cutover.
7. Restrict the web API key by HTTP referrer and the Android/iOS keys by app
   identity in Google Cloud → Credentials.
8. Create the first administrator out of band (Console user + `/users/{uid}`
   profile with `role` and `status: ACTIVE`).

**Signing (F-REL-2)**
1. Generate an upload keystore on a trusted machine (not in the repo):
   `keytool -genkeypair -v -keystore <NAME>.jks -keyalg RSA -keysize 2048 -validity 10000 -alias <ALIAS>`; back it up in your secret manager.
2. Create `android/key.properties` (git-ignored) with `storeFile`,
   `storePassword`, `keyAlias`, `keyPassword`; in CI write it from secrets.
3. `flutter build appbundle --release --build-name <X.Y.Z> --build-number <N>`;
   confirm with `apksigner verify --print-certs` that it is **not** the debug
   certificate. Enrol in Play App Signing.
4. iOS: Apple Developer team, distribution certificate, App Store profile for
   the bundle id; `flutter build ipa --release`; install the iOS 26.5
   platform (Xcode → Settings → Components) on the build Mac.

## 10. Revised release recommendation

**NOT READY FOR RELEASE (production).** Code-level blockers found by the audit
are closed or have a documented, bounded residual. What remains is
owner-supplied: real Firebase environments and options, signing keys, enabled
and rehearsed backups, a first staging run (rules, indexes, OAuth, smoke
tests), the parent-access backfill at cutover, and acceptance of F-FIN-1
(pilot-only rules-based finance) and F-SEC-4. When §9 steps 1–6 and §7 are
done and the staging smoke tests pass, the recommendation becomes **READY FOR
STAGING → PRODUCTION on your approval**.
