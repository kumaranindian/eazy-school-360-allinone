# Milestone 12 — Production Hardening & Release Readiness

> **Update — Milestone 12A (see `docs/milestone-12a-blocker-closure.md`):**
> F-SEC-3 is fixed in code and rules (needs the documented backfill at cutover),
> F-DEP-1 has a working scan (0 Dart advisories; 5 high in npm test tooling),
> F-OPS-1/2 were validated locally and two CI-breaking defects fixed, F-FIN-1 and
> F-DATA-1 have an architecture / exact procedures. Two new P1s were found and
> fixed (F-REL-3 Firebase options model, F-OPS-3 option files git-ignored).
> Recommendation unchanged: **NOT READY FOR RELEASE**, with the remaining
> blockers now owner/operations actions.

**Release recommendation: NOT READY FOR RELEASE** (production).
Code-level security and integrity checks pass; the blockers are configuration
and operations that only the project owner can supply (see §11). Staging is
possible as soon as the staging Firebase project is configured (§12).

Nothing was deployed, published or written to live data in this milestone.
Milestones 0–11 were *re-verified from source and tests*, not assumed.

## 1. Audit scope and method

Inspected: architecture and folders; `pubspec.yaml`/lock; auth, session and
tenant context; router guards; role/permission matrix; all 64 branch-level
Firestore collections and 10 Storage path patterns; indexes; environment
files; Android/iOS/web identity and signing; logging and error mapping;
test suites; CI. There are **no Cloud Functions or other backend services**
in the repository — everything privileged is expressed as Firestore/Storage
rules (see Known limitations).

Evidence is the source, the rules, and executed commands. Items that need a
real Firebase project, store credentials or devices are marked **untested**.

## 2. Baselines (before this milestone) and final results

| Check | Baseline (end of M11) | Final (M12) |
|---|---|---|
| `dart format --output=none --set-exit-if-changed .` | 0 changed | 0 changed (451 files) |
| `flutter analyze` | no issues | no issues |
| `flutter test` | 863 passed | **877 passed** (+14) |
| Rules suite (emulator, serial) | 263 passed | **281 passed** (+18) |
| `flutter build web --release` | (debug-profile web built in M11) | see §13 |
| `flutter build apk --release` / `appbundle --release` | not run before | see §13 |
| `flutter build ios --release` | blocked (iOS 26.5 platform) | see §13 |

New tests: 8 invoice reconciliation, 6 session/startup (account switch,
sign-out, protected deep link, startup error screen, error handlers, staff
branch reset), 11 tenant sweep (Firestore) + 7 tenant sweep (Storage).

## 3. Findings

Severity: P0 data exposure/cross-tenant/auth bypass/corruption; P1 major
workflow, release-blocking; P2 reliability/maintainability; P3 minor.

### P0 — none confirmed
A generic sweep (below) found **no cross-school read or write** in any
collection or Storage path.

### P1
| ID | Finding | Status |
|---|---|---|
| F-REL-1 | Firebase options for **all four environments are placeholders** (`REPLACE_WITH_FLUTTERFIRE_CONFIGURE`). UAT/prod builds started silently and every request failed. | **Mitigated in code** (UAT/prod now stop on a clear screen; `EnvConfig.hasPlaceholderFirebaseOptions`). **Open:** run `flutterfire configure` per environment. **Release blocker.** |
| F-REL-2 | Android `release` was signed with the **debug key**. | **Mitigated in code** (`android/key.properties` support; without it a Gradle warning is logged — not visible in Flutter's filtered build output, so the APK/AAB artefacts must be checked). **Open:** create and supply the upload keystore. **Release blocker** for store builds. |

### P2
| ID | Finding | Status |
|---|---|---|
| F-SEC-1 | After an account switch the previous user's profile stayed in the tenant context while the new one loaded; the old shell/navigation remained visible. | **Fixed** (app-level gate rebuilds the navigator; router checks uid) + regression tests. |
| F-SEC-2 | Staff screens' selected branch survived an account change. | **Fixed** + test. |
| F-SEC-3 | A **parent can read published homework, announcements, broadcast notices and examinations of any branch of the same school**, and live timetable/substitutions (rules cannot tie a parent to a class/section). Never crosses schools; drafts are hidden. | **Open — product decision.** Pinned by the sweep as a *known* exposure so any new leak fails. Remediation options in §4. |
| F-ERR-1 | No global handler for unhandled Flutter/platform errors. | **Fixed** (`installErrorHandlers`, routed to `AppLogger`; no detail shown to users). |
| F-OPS-1 | No CI. | **Added** `.github/workflows/ci.yml` (format, analyze, tests, web build, rules). *Not executed here* (no GitHub runner). |
| F-OPS-2 | No web hosting configuration or security headers. | **Added** hosting block (SPA rewrite, nosniff, frame-deny, referrer, permissions, HSTS, no-cache for entry files). CSP deliberately not added (cannot be validated without a browser/hosting run). |
| F-FIN-1 | Invoice/receipt numbering, arithmetic and idempotency are enforced by rules and client transactions, not a trusted server. | **Accepted limitation**; strongly tested (§5); reconciler added. |
| F-DATA-1 | Backups/PITR cannot be configured from the repo. | **Open — operator step** (§9). |
| F-DEP-1 | No vulnerability scanner available for this SDK (`dart pub audit` absent in Dart 3.8/Flutter 3.32.8). | **Open** — run OSV/`pub.dev` advisories in CI on a newer SDK. |

### P3 (deferred)
Overlapping `notifications` match blocks (3, OR-ed by design); `cupertino_icons`
unused by Dart imports (kept for iOS); `leaveTypes` listener lacked a bound
(**fixed**: `limit(200)`); go_router 17→18 and file_picker 11→13 majors not
taken (no justified need); iOS 26.5 SDK missing in this environment.

## 4. Security and tenant isolation

* **Sweep (`tenant-sweep.test.mjs`)** reads `firestore.rules`, discovers every
  branch collection (64), seeds a normal and a "published/live" document in
  School A / North, and has 10 foreign actors (signed out; SCHOOL_ADMIN,
  BRANCH_ADMIN, TEACHER, FINANCE, PARENT of another school; BRANCH_ADMIN,
  TEACHER, FINANCE, PARENT of another branch) try get, list, create, update
  and delete. Result: **no cross-school access; no cross-branch write; no
  cross-branch read except the documented list**: `leaveTypes` (school
  configuration), schedule data readable by parents (F-SEC-3), and
  published parent-addressed content (F-SEC-3).
* **Storage sweep (`tenant-sweep-storage.test.mjs`)**: 10 path patterns × 7
  foreign actors × read/add/overwrite/delete — all denied (logo is school-wide
  by design).
* Earlier suites keep covering role forging, parent↔child links, teacher
  assignment scope, finance scope and platform-admin rules (281 passing tests).
* Router/session: protected routes, deep links while signed out, disabled and
  invited accounts, account switch and sign-out are covered by widget tests.
* No secrets: no service-account material, private keys or tokens in `lib/`,
  `android/`, `ios/`, `web/`. Firebase API keys are public identifiers.
  `.gitignore` now excludes key stores, `key.properties`, `.env*`.

**F-SEC-3 remediation options** (needs owner decision): (a) a trusted backend
that maintains per-parent placement keys (custom claims or a rules-readable
document) so rules can match class/section; (b) restrict parents to their
profile branch (breaks families with children in several branches); (c) accept
(content is addressed to parents and low sensitivity).

## 5. Financial integrity

Verified by the existing rules suite (re-run, passing) — 33 fee tests:
tenant/branch isolation; teachers none; parents read only linked child;
invoice arithmetic (`payable = subtotal − discount`, `balance = payable −
waived − paid`); one invoice per student/period; unique, sequence-bound
invoice and receipt numbers; payments inseparable from invoice update and
receipt; overpayment refused by one minor unit; concurrency (two cashiers on
the same balance); idempotency (same payment id twice, replay); payments and
receipts immutable; reversal admin-only, once, with reason, invoice restored,
history kept; waivers bounded; voids only when nothing paid; append-only
audit log.

Added: `InvoiceReconciler` (pure, read-only) cross-checks an invoice with its
payments: subtotal/discount/payable, paid vs active payments, balance, status,
duplicate receipts, foreign/cross-student payments, void with payments. It
reports; it never writes.

**Reconciliation procedure** (documented, not yet exercised on real data):
1. Export the branch's invoices and payments (read-only, finance admin).
2. Run the reconciler per invoice; collect codes.
3. For each finding decide the *business* truth from receipts/bank records.
4. Correct only by new attributable transactions (reversal, waiver, void +
   re-issue); never edit or delete a payment, receipt or audit entry.
5. Re-run the reconciler; archive the report with approver names.

Residual risk: rules can verify a commit's documents against each other but not
aggregate sums across many documents; a malicious finance user using the SDK
directly is bounded by the rules above, but a trusted backend would be needed
for independent totals and for secure numbering under extreme contention.

## 6. Data-integrity and business rules

Re-verified through the milestone suites: ownership (school/branch) on every
write; academic-year/class/section relations; enrolment history preserved;
parent-student links; teacher assignment slots; attendance uniqueness and
revision history; leave balances and ledger; timetable/substitution locks;
homework and marks revision histories; result versions create-only;
notification deterministic ids; conversation membership. No silent deletions:
history collections are append-only; records are voided, closed or archived.
No new defects found beyond §3 in these modules during this audit.

## 7. Database and performance

* Static scan of all 20 `q.get()/q.snapshots()` sites: all bounded by `limit`
  or pagination except `leaveTypes` (now limited). Remaining unlimited reads are
  equality-scoped to a section/student/exam/year (bounded by roster size).
* Indexes: 82 composite indexes, including `conversations` and
  `messageContacts` from M11. Not exercised by the emulator; deploy and watch
  for "index required" errors in staging.
* Listeners: bell + centre share one bounded listener per branch; conversation
  list one per branch; threads limited to 30; autoDispose throughout; failed
  loads do not retry in the background.
* Cost notes: dashboard issues no queries; notification unread count is one
  aggregate per branch; `timetableEntries where live` per academic year is the
  largest scan (≈ sections × days × periods, low thousands) — cached per screen.
* No change removed real-time behaviour.

## 8. UI, errors, observability

* Duplicate-submission guards, confirmations for destructive actions, and
  responsive layouts exist and are covered by widget tests at 390–1400 px.
* Errors: `mapExceptionToFailure`/`userMessageFor` keep technical detail in
  logs only; global handlers added; startup misconfiguration shows a neutral
  screen. `AppLogger` is the single hook for a crash reporter; **no crash
  reporting service is configured** and none was added (would need a project
  and a privacy review).
* Logging policy unchanged: no passwords, tokens, message bodies or payment
  secrets.

## 9. Backup, recovery and incident procedures (documented — **not tested**)

| Scenario | Procedure |
|---|---|
| Firestore backup | Enable scheduled backups and point-in-time recovery for the production database; retention ≥ 7 days; restrict to owners. |
| Accidental deletion/corruption | Restore a backup/PITR snapshot into a **new** database, diff against production with the reconciler and read-only exports, then copy back only the affected collections via an audited script. Never restore over live data without sign-off. |
| Storage files | Enable object versioning/soft delete on the bucket; restore by copying the previous generation; rules are create-only so overwrites are rare. |
| Verify a restore | Run the reconciler on invoices; compare document counts per collection; spot-check results versions and conversation counters. |
| Rollback a release | Web: redeploy previous hosting version. Mobile: halt staged rollout, ship previous build. Rules: redeploy the previous `firestore.rules` from git tag. Keep rules and app releases backward-compatible one version. |
| Failed notification/job | There are no background jobs; notices are written with the business change. A missing notice is re-created by repeating the action (idempotent ids). |
| Financial inconsistency | §5 procedure. |
| Compromised credential | Rotate the Firebase API restrictions, revoke affected refresh tokens (`revokeRefreshTokens` via Admin SDK), disable the user, review audit logs, rotate any service account. |
| Account access incident | Disable the profile (`status: DISABLED`) — the app and rules deny; review `financialAuditLogs`, `*History` collections. |

## 10. Dependency and configuration audit

* 9 direct dependencies, all within one minor/major of latest; **no unused
  runtime dependency** except `cupertino_icons` (conventional). No upgrade was
  applied: none is required for correctness or a known advisory, and major
  jumps (go_router 18, file_picker 13) add risk without need.
* Not verifiable here: advisories (no scanner for this SDK), OAuth authorised
  domains, SHA fingerprints, iOS signing — all need the real project/accounts.
* Application ids: `com.avail404.eazyschool.eazyschool360` (Android namespace
  and applicationId, iOS bundle id) are consistent. Version `1.0.0+1`.
* Environment separation: four entrypoints and option files exist; none is
  configured.

## 11. Release blockers and untested areas

**Blockers (must be cleared by the owner):**
1. Real Firebase projects and options for staging/UAT/prod (F-REL-1).
2. Android upload keystore and `key.properties` (F-REL-2); iOS signing/profile.
3. Decision on F-SEC-3 (accept, or fund a trusted placement backend).
4. Backups/PITR and monitoring configured and a restore rehearsed (§9).
5. A staging run against real Firebase: rules + indexes deployed, smoke tests
   (§12), Google sign-in/OAuth domains verified.

**Verified failures:** none in code or tests at the time of writing.
**Untested:** live Firebase behaviour (emulator only), index build, real
devices/browsers, push (not implemented), crash reporting, CI execution,
store submission, iOS release build (platform missing in this environment).

## 12. Production deployment checklist (do not run without approval)

1. Select project: `firebase use <staging|prod>`; confirm `projectId` in the
   matching `firebase_options_*.dart` and the flavor `main_*.dart`.
2. Authentication: enable Email/Password and Google; add authorised domains
   (hosting domain, localhost removed in prod); Android SHA-1/256, iOS bundle.
3. `firebase deploy --only firestore:rules,firestore:indexes,storage` — wait
   for indexes.
4. Hosting: `flutter build web --release`; `firebase deploy --only hosting`;
   verify HTTPS and the headers.
5. Android: `android/key.properties` + keystore; `flutter build appbundle
   --release --build-name X --build-number N`; upload to internal track.
6. iOS: signing identity/profile; `flutter build ipa --release`.
7. Provision the first platform/school admin out of band; no default accounts.
8. Enable backups/PITR, billing alerts, auth anomaly alerts, log retention.
9. Smoke tests: sign in each role; parent sees only own child's invoice;
   teacher cannot open fees; admin issue → pay → reverse an invoice; publish
   homework and see the notification; send and read a parent–teacher message;
   sign out/in as another user and confirm no stale data.
10. Rollback plan from §9 agreed and the previous artefacts retained.

No production secret belongs in this repository or these documents.

## 13. Build results (actual, executed 2026-10-10)

| Command | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 451 files, 0 changed |
| `flutter analyze` | No issues found |
| `flutter test` | 877 passed, 0 failed |
| rules suite (`firebase emulators:exec --only firestore,storage …`) | 281 passed, 0 failed |
| `flutter build web --release` | ✓ built `build/web` |
| `flutter build apk --release` | ✓ built `app-release.apk` (68.0 MB) — **signed with the debug key** (no `key.properties`); not publishable |
| `flutter build appbundle --release` | ✓ built `app-release.aab` (52.4 MB) — **debug-signed**; not publishable |
| `flutter build ios --release --no-codesign` | ✗ **blocked**: iOS 26.5 platform not installed in Xcode (Settings → Components) |

Gradle printed Kotlin metadata-version messages for Firebase modules during the
APK build; the build succeeded. Treat as P3 (dependency toolchain alignment).
Not run: store upload, signed builds, `firebase deploy` (no approval/credentials).

## 14. Known limitations

No trusted backend (numbering/idempotency rely on rules); parents' read scope
is school-wide for published content (F-SEC-3); push, attendance/fee
notification triggers, retention cleanup and crash reporting are not
implemented; attachments cannot be read by administrators of reported
conversations; PDF built-in fonts are Latin-1 only.
