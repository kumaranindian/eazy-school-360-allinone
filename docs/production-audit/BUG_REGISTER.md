# Bug register

Audit of `develop` @ `f36c35f` (2026-10-17). Nothing here has been fixed. **Verified** column: **L** = the lead auditor read the cited code and confirmed the defect; **S** = reported by a read-only sub-audit with file:line evidence that the lead did **not** re-read — treat as CONFIRMED-by-report until a fix's regression test reproduces it first. Confidence follows the brief (CONFIRMED / HIGHLY LIKELY / POTENTIAL / UNKNOWN). No finding is a demonstrated cross-tenant data leak: the tenant-isolation rules suite passes (see TEST_RESULTS.md); there are **no P0**.

Counts (confirmed + highly likely, excluding potentials and unknowns): **P0: 0 · P1: 6 (plus OPS-1, an unverified gate blocker) · P2: 25 · P3: 13.**

## P1 — high

| ID | Title | Conf. | Ver. |
|---|---|---|---|
| SEC-1 | `firestore.rules` is 223,727 B of a ~256 KiB release limit; the team's own tool records full-file releases being refused | HIGHLY LIKELY | L (partial) |
| NOTIF-1 | Previous user keeps receiving pushes on a shared device after any sign-out except the app-bar button | CONFIRMED | L |
| NOTIF-3 | A failed push delivery is never retried or redriven (FAILED / stuck PROCESSING are terminal) | CONFIRMED | S |
| ACAD-1 | Academic-year dates stored as local midnight, read via `.toUtc()` → every boundary is a day early in UTC+ zones (India) | CONFIRMED | L |
| CFG-1 | Release builds silently fall back to the **debug** signing key when `key.properties` is missing | CONFIRMED | L |
| OPS-1 | No backup / PITR / restore drill exists in repo or evidence (`UNKNOWN — REQUIRES VERIFICATION` in the cloud project) | UNKNOWN (gate blocker) | — |
| OPS-2 | Crash reporting is incomplete on Android/iOS: no Crashlytics Gradle plugin / iOS symbol upload; no alert policies in repo | CONFIRMED (absence) | L |

### SEC-1 — Rules size / deployability
* **Evidence:** `wc -c firestore.rules` = 223,727. `tool/patch_dev_push_rules.js:19-37` states the full file "is currently refused at release time (INVALID_ARGUMENT)… +773 bytes was refused, -1 byte was accepted" and that the dev project still runs older live rules. Upstream already shaved rules to fit (`nd()`/`newInTenant()` helpers, `firestore.rules:23-38`).
* **Impact:** every security rule added since the live ruleset (teacher scoping, multi-branch, push devices…) may **not be live**. What is deployed in dev/prod is UNKNOWN.
* **Repro:** `firebase deploy --only firestore:rules --dry-run --project <dev|prod>`.
* **Fix:** split headroom — factor repeated predicates, drop dead helpers, consider moving per-feature rule logic into fewer wider `match` blocks; add a CI step that fails above e.g. 200 KB and a dry-run deploy to the dev project.
* **Test:** CI size gate + dry-run; `firestore-tests` (437 pass) after refactor.

### NOTIF-1 — Sign-out leaves device registered
* `lib/core/routing/app_shell.dart:420-423` is the **only** caller of `unregisterPushDevice`. `account_inactive_page.dart:73` and `create_school_page.dart:23` call `signOut()` directly; session revocation (`functions/access.js` `revokeRefreshTokens`) also skips it. `push_providers.dart:87-101` swallows every failure and the callable needs a valid token. `functions/push.js` sends to every non-INACTIVE device doc of a uid; nothing expires devices.
* **Repro:** A signs in on a phone, hits *Sign out* on the "account inactive" page (or signs out offline); B signs in. A's notices keep arriving on B's phone.
* **Fix:** unregister centrally before every sign-out with a short timeout (also fixes STATE-3), expire devices by `lastSeenAt`, delete devices when status/`login.enabled` changes.
* **Test:** widget test per sign-out path expecting `removeDevice`; `functions/push.test.js` stale-device skip.

### NOTIF-3 — No redrive of failed deliveries
* `functions/index.js` triggers catch all errors and write FAILED; `delivery_log.js` only takes over stale PROCESSING; no retry flag, no sweeper, no explicit `timeoutSeconds`. A transient Firestore/FCM error loses the notice (a fee-due or absence alert) with only a log line.
* **Fix:** `retry: true` + re-runnable FAILED claims, or a scheduled sweeper over `pushDeliveries`; raise timeout. **Test:** resolver throws once, redelivered event sends.

### ACAD-1 — Academic-year time-zone off-by-one
* **Write:** pickers return local `DateTime(y,m,d)`, stored as-is (`academic_year_form_dialog.dart`, `school_year_dialogs.dart:44-52`, `academic_year.dart` / `school_academic_year.dart` `Timestamp.fromDate`). **Read:** `…startDate.toUtc()` → `AttendanceDate.key` in `timetable_scope.dart:34-35`, `leave_scope.dart:33-34`, `leave_apply_form.dart`, `substitution_pages.dart:85-86,577-578`, `timetable_hub_page.dart:297-299`, `exam_results_page.dart:103`, `leave_balances_page.dart:259`; attendance reads it as local (`calendar_support.dart:63-67`). Holidays are normalised to UTC midnight and are correct.
* **Repro (IST):** admin enters 2026-04-01 → 2027-03-31 (stored 2026-03-31T18:30Z / 2027-03-30T18:30Z). Leave on 31 March is rejected "outside the academic year"; leave balances start a day early; timetable/substitution ranges end a day short.
* **Impact:** wrong accrual, blocked last day, ranges cut — **existing data is affected** in every UTC+ deployment. The new school-wide year registry (this session's work) copies the same storage shape, so the registry year should be fixed before schools adopt it.
* **Fix:** write `DateTime.utc(y,m,d)` and add `startDateKey/endDateKey` strings (validate in rules); migrate old documents; read keys only.
* **Test:** run date suites with `TZ=Asia/Kolkata` and `TZ=America/Los_Angeles` (CI matrix); a year 2026-04-01…2027-03-31 yields identical keys in leave/timetable/attendance.

### CFG-1 — Debug-signed release
* `android/app/build.gradle.kts:62-71`: `signingConfig = signingConfigs.getByName("debug")` with only `logger.warn`. A CI/dev `flutter build appbundle` without `android/key.properties` produces a debug-signed artifact. **Fix:** fail the build when `CI` or `-Prelease` is set and the key is absent. **Test:** `flutter build appbundle` without the key must fail.

### OPS-1 / OPS-2 — see PRODUCTION_CONFIGURATION_AUDIT.md and PRODUCTION_GAP_REGISTER.md.

## P2 — medium

| ID | Title | Conf. | Ver. | Fix (one line) |
|---|---|---|---|---|
| STATE-1 | Students & Parents list pages: double "Load more", out-of-order search overwrites newer, error leaves endless spinner (`students_list_page.dart:59-112`, `parents_list_page.dart:101-142`; `directory_list.dart:253`) | CONFIRMED | L | migrate to the shared `PagedListController` (already used by staff/invoices/payments) |
| STATE-2 | Same out-of-order/no-error handling in `leave_balances_page.dart:63-93`, `link_parent_dialog.dart:58-72`, `student_admission_page.dart:78-91` | CONFIRMED | S | request token + try/catch/finally |
| UI-1 | Admission reports "admitted successfully" even if guardian create/link failed (`student_admission_page.dart:176-203`) | CONFIRMED | L | check both results, route to link dialog on failure |
| UI-2 | Results finalised with silently missing attendance (`exam_results_page.dart:105-132` `catch (_)`) | CONFIRMED | S | count failures, ask before finalising |
| ACAD-2 | Admission number uniqueness is check-then-write; no reservation doc; case/space-sensitive (`firebase_student_repository.dart:311-370`; also used by `transferToBranch`) | CONFIRMED | L | `admissionNumbers/{lower}` create-only reservation in the same batch + rule (as `staffCodes`) |
| ACAD-3 | Marks save commits in chunks of 5; partial failure + stale revisions make every retry fail until reload (`firebase_exam_repositories.dart:593-700`, `marks_entry_page.dart:294-296`) | CONFIRMED | S | reload & rebase on failure, report written count |
| ACAD-4 | `approvedSheets` counter is read-then-batch-write; concurrent approvals of different sheets → one gets a generic permission error (`firebase_exam_repositories.dart:764-823`, rule `examApprovedMovesBy`) | CONFIRMED | S | `runTransaction` or `FieldValue.increment` |
| ACAD-7 | In-branch student transfer not transactional → two concurrent transfers can leave two ACTIVE academic records (`firebase_student_repository.dart:534-615`) | HIGHLY LIKELY | S | transaction with expected-record precondition, deterministic record id |
| ACAD-9 | Attendance rules trust the `classId/sectionId` in the written doc and cannot verify enrolment/calendar; a class teacher can create a record for any student id of the branch with their own section, blocking the real teacher (`firestore.rules` attendance block, `attendance_save_planner.dart:274-278`) | HIGHLY LIKELY | S | in rules `get(student)` and require current section; tie `dateKey` to `attendanceDate` |
| NOTIF-2 | `login.enabled=false` (still ACTIVE) users keep receiving pushes and can register devices (`push.js eligibleUsers`, `devices.js activeSchoolUser`) | CONFIRMED | S | require `login == null \|\| login.enabled` |
| NOTIF-4 | Recipients silently truncated at 2000 (`push.js` `slice(0, MAX_RECIPIENTS)`) | CONFIRMED | S | page the fan-out, record `truncated` |
| LOG-1 | PII into Crashlytics: `AppLogger.error('Sign up failed for email: $email')` (`firebase_auth_repository.dart:148-149`) and student name in fee-chunk error (`firebase_invoice_repository.dart:243`) reach `errorSink` (`monitoring_setup.dart`) | CONFIRMED | L | log uid/ids only; unit test asserting no `@` |
| ROUTE-2 | No deep-link/refresh restoration: unresolved auth → `/`, signed-out → `/login`, nothing remembers the target (`app_router.dart:62-100`) | CONFIRMED | L | carry `?from=` and consume after tenant resolves |
| STATE-3 | Sign-out awaits the unregister callable (no timeout, default ~70 s) before `signOut` (`app_shell.dart:420-424`) | HIGHLY LIKELY | S | 4 s timeout, sign out regardless |
| SEC-2 | App Check off by default (client opt-in define; server `ENFORCE_APP_CHECK` false) so unauthenticated `requestPhoneOtp`/`verifyPhoneOtp` rely on rate limits only | CONFIRMED | S | enable in prod after registration (docs/app-check-and-monitoring.md) |
| SEC-3 | OTP: lock-out of a victim's number by superseding codes; per-IP key from `rawRequest.ip` (real client IP behind the proxy UNKNOWN); no TTL on `otpChallenges/otpRate` | HIGHLY LIKELY | S | App Check, TTL fields, verify IP source |
| SEC-4 | `feeDueReminders` scans `collectionGroup('invoices')` of ALL tenants with `limit(2000)` and sequential reads; later tenants silently skipped (`index.js:150`, `notify_events.js:246-275`) | CONFIRMED | S | iterate per school/branch with paging; timeout/memory |
| CFG-4 | Hosting has no `Content-Security-Policy` / COOP, no long-cache for hashed assets (`firebase.json:46-71`) | CONFIRMED | S | CSP verified in a real browser |
| CFG-6 | Staff list filters chain `status + department/designation/employmentType/isTeacher + orderBy(displayNameLower)` but only single-filter composites exist (`firebase_staff_repository.dart:127-150` vs `firestore.indexes.json`) → `failed-precondition` on combined filters / the default ACTIVE + department view | HIGHLY LIKELY | L (static) | add the composites or restrict to one server filter |
| CFG-7 | CI: no `permissions:`, actions on mutable tags, `npm i -g firebase-tools` unpinned, no timeout/concurrency | CONFIRMED | S | least-privilege token, pin by SHA |
| DEP-1 | `functions` deps: `npm audit --omit=dev` → 9 vulns (2 high: `node-forge` via `firebase-admin@12`; 7 moderate incl. `uuid`) | CONFIRMED | L | upgrade `firebase-admin`/`firebase-functions` (breaking) and re-test; confirm whether the forge code path is reachable |
| PERF-1 | Finalise results: one `fetchStudentRange` per student (~120 sequential round-trips, ~25 k reads/finalise) (`exam_results_page.dart:105-130`) | CONFIRMED | S | one section-level range query |
| PERF-2 | *Refresh parent access* is a sequential per-parent loop with no progress/reentrancy guard (`parent_access_sync.dart:83-160`) | CONFIRMED | S | chunked parallel + progress + busy flag |
| ACAD-6 | Scheduled announcements notify immediately; push ignores `publishAt` (`firebase_announcement_repository.dart:149-190`; no `publishAt` in `functions/*.js`) | CONFIRMED | S | skip/defer notices with future `publishAt` |
| OPS-3 | No alert policies / budget alerts / uptime checks in repo or evidence (docs only) | UNKNOWN | — | create Cloud Monitoring policies for Functions errors, auth anomalies, billing; record in runbook |
| OPS-4 | Single-document counters (`invoice`/`receipt` per year) serialise all billing in a year (~1 write/s) — fine for pilots, a ceiling at scale | CONFIRMED (design) | L | shard or per-register series if volume demands |

## P3 — low
NOTIF-5 (stale-claim takeover not atomic), NOTIF-6/7 (lock-screen content; `ALL` pushes to staff who cannot open the notice), ACAD-5 (NaN / multi-decimal marks components pass client validation; rules reject), ACAD-8 (finalise can freeze stale marks if sheets change after calculation — POTENTIAL), STATE-4 (`addReadIds` lost update), STATE-5 (small lifecycle gaps), STATE-6 (late `switchBranch` can overwrite tenant after sign-out — introduced this session; fix: capture uid before the await), ROUTE-1 (three routes missing from `requiredPermissions`; guarded in-page and by rules), LOG-2 (raw `debugPrint` of callable error bodies in release), CFG-5 (`storage.cors.json` `origin:*` — applied or not UNKNOWN), CFG-9 (`.gitignore` lacks `*.p8/*.p12/*.pem/*.mobileprovision/serviceAccount*.json`), CFG-3/10 (Android `allowBackup` default, no `PrivacyInfo.xcprivacy`, shared app id for dev/prod), SEC-6 (SVG allowed by `image/.*`; no self-signup spam control), PERF-3 (bulk import one query per row).

## Potentials / unknowns (not counted)
ACAD-10 (leave day-locks not required by rules; client clock for decisions), ACAD-11 (timetable not re-validated after slot changes), ACAD-12 (homework `dueAt` TZ), ACAD-13 (holiday duplicate by double tap; working-day history client-computed), ACAD-14 (grade from rounded percentage; absent policy — confirm intent), ACAD-15 (staff status change non-atomic), STATE-7 (Firestore on-device persistence not cleared at sign-out — UNKNOWN on real devices), registerDevice token-move race (fail-safe), push `quota-exceeded` treated as permanent.
