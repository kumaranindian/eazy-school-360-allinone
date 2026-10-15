# RBAC, Security Rules & Permission-Flow Audit — EazySchool 360

Audit date: 2026-10-15 · Branch: `develop` · Reviewer: automated audit + emulator tests.

**What was and was not verified.** Everything below was checked against the repository and the Firebase **emulator** (`firestore-tests/`, 327 rules tests). No production or dev Firebase project was reachable from the audit environment, so *live* rules, live data and live logs were **not** inspected. Findings are labelled:

* **CONFIRMED-TEST** — reproduced as a failing emulator test, fixed, test now green.
* **CONFIRMED-CODE** — proven by reading code/rules, no behavioural test possible or needed.
* **VERIFY** — plausible from the code but depends on live data/config; a check is provided.

## 1. Existing architecture and authentication flow

Stack: Flutter (web/Android/iOS), Firebase Auth, Cloud Firestore, Storage, Cloud Functions (Node, `asia-south1`), Riverpod, GoRouter.

Login → first query, for every role (`lib/core/...`):

1. `main_<env>.dart` selects the Firebase project (`lib/core/config/firebase_options/`).
2. `authStateChangesProvider` (Firebase Auth stream) → router guard `appRouterProvider` (`app_router.dart`).
3. `TenantContextNotifier` (`lib/core/tenant/tenant_context_provider.dart`) — the **single** place that resolves identity:
   `users/{uid}` → status → `login` map / sign-in method check → `schools/{schoolId}` → `branches/{branchId}`.
4. States already modelled: loading (splash), signed-out, **no profile → `/create-school`**, non-ACTIVE / login disabled / method not permitted / **invalid profile** → `/account-inactive`, other errors → splash with retry. Account switching: the router refuses a tenant context whose `userId` ≠ current uid.
5. Permissions: `RolePermissions.grants` (UI only). Route permissions: `AppRoutes.requiredPermissions`.
6. Role-specific data is *not* preloaded; each screen's repository issues its own queries (see §4). Dashboard itself reads nothing but the tenant context.

Authorization is enforced **only** by `firestore.rules` / `storage.rules` / Cloud Functions. Rules look up the caller's `/users/{uid}` profile (no custom claims), plus relationship records:
teacher ⇒ `staff.userId` + `teacherAssignments` + `assignmentSlots`; parent ⇒ `users.linkedParentId` + `parents/{id}` + `students/*/parentLinks` + `parentAccess/{id}`.

## 2. Actual schema (authorization-relevant)

| Path | Key fields | Written by |
|---|---|---|
| `users/{uid}` | `schoolId`, `branchId`, `role`, `status`, `linkedParentId`, `login{enabled,methods,effective,phone}` | admin (profile fields) / **Cloud Functions only** (`login`) |
| `schools/{s}` | profile, `authSettings/methods`, `authAudit/*` (server-written) | school admin / functions |
| `schools/{s}/branches/{b}` | status | admins |
| `.../staff/{id}` | `userId` (login link), `status`, `isTeacher` | managers |
| `.../teacherAssignments/{id}` | `teacherStaffId`, `academicYearId`, `classId`, `sectionId`, `subjectId`, `isClassTeacher`, `status` | managers (rules verify refs) |
| `.../assignmentSlots/{year__class__section__(subject\|CLASS_TEACHER)}` | `teacherStaffId` — uniqueness + the **thing attendance/marks rules check** | written in the same batch as the assignment |
| `.../students/{id}` | `currentAcademicYearId/ClassId/SectionId`, `status` | managers |
| `.../students/{id}/parentLinks/{parentId}` | `schoolId`,`branchId`,`parentId`,`studentId`,`status`,`canAccessPortal` | managers / `provisionLogins` |
| `.../parents/{id}` | `linkedUserId`, `status` | managers |
| `.../parentAccess/{parentId}` | `classKeys[]`, `sectionKeys[]` — rules-readable index of where a family has children | managers / functions (never the family) |
| `.../announcements`, `broadcastNotices` | `audienceKind`, `classId`, `sectionId`, `status` | authors (rules tie notice ↔ document) |

Every tenant document carries `schoolId` (and `branchId`); rules validate them against the **path** on write and, for list queries, against the caller's profile.

## 3. Findings

| # | Sev | Finding | Status | Fix |
|---|---|---|---|---|
| C1 | **Critical** | The rules in the repo may not be what is deployed. The ruleset is large (231 KB source); a commit (`17e4481`) documents a project whose *live* rules predate push notifications and where the full file was refused at release. Every teacher/parent symptom below can also come from stale live rules. | VERIFY | Compare live vs repo (§7). Rules were also shrunk once (`8614984`); this change adds ~3 KB — re-run the release dry-run. |
| H1 | High | `PLATFORM_ADMIN` passes every `staffScope`/`isSchoolAdminOrAbove` check ⇒ blanket read/write of **every school's** data incl. finance. Contradicts "never expose sensitive school data to ordinary platform users". No UI depends on it. | CONFIRMED-CODE | Not changed (would need a support-access workflow). Plan §6.1. |
| H2 | High | **Teacher: the year-wide ACTIVE assignment list is denied.** `yearAssignmentsProvider` queries `teacherAssignments` by year+status without `teacherStaffId`; the read rule only allowed owner/manager. It feeds the announcement viewer (⇒ whole Announcements page errors), the notification centre/bell (⇒ feed error, bell 0), homework create/edit, Parent-messages toggle, marks-sheet lists. | CONFIRMED-TEST (`T1`) | Rule: ACTIVE assignments readable by teachers of the branch (no personal data; already visible via the live timetable). |
| H3 | High | **Reads of documents that do not exist yet are denied.** Rules for `attendanceSessions`, `marksSheets`, `homeworkSubmissions`, `resultSummaries` dereference `resource.data`; for a missing doc `resource` is null ⇒ error ⇒ `permission-denied` for everyone except the admin short-circuit. The app treats "missing" as "not started": class teachers cannot open a day's register, subject teachers a new marks sheet, parents a child's homework (before submitting) or result. | CONFIRMED-TEST (`M1–M4`) | Rules rebuild the needed fields from the document id (same ids the create rules enforce) when `resource == null`. |
| H4 | High | **Parent with no `parentAccess` index is denied the entire announcements/notices query** (rules are not filters: the 5-audience `in` query cannot be proven without the index although `ALL` is theirs to read). Contradicts "announcements are school-wide". | CONFIRMED-TEST (`CONFIRMED:` test) | App retries with `audienceKind == ALL` on exactly that refusal (`runWithParentFallback`, unit-tested). Rules unchanged. |
| M1 | Medium | **Parent: invoice detail payments** queried by `invoiceId` only ⇒ unprovable ⇒ denied. | CONFIRMED-TEST (`P4`) | Query pinned to the invoice's `studentId`. |
| M2 | Medium | **Teacher: Parent profile "children"** — collection-group `parentLinks` query without `branchId` ⇒ denied for branch-scoped roles. | CONFIRMED-TEST (`T3`) | Query pinned to the branch; new index `(schoolId, branchId, parentId)`. |
| M3 | Medium | **Parent: leave-apply form** needs the academic-year *dates* but read the staff-only years list. | CONFIRMED-TEST (`P5`) | Families may `get` one `academicYears/{id}` of a branch where they have a child (never list); form uses the child's `currentAcademicYearId`. |
| M4 | Medium | **Teacher: homework form** listed colleagues' staff records (personal data, correctly denied) only to label options. | CONFIRMED-TEST (`T2`) | Not fetched for teachers; staff list stays private. |
| M5 | Medium | `leaveHistory` detail query (3 equalities + `orderBy`) had no composite index ⇒ `failed-precondition` for teachers/parents/admins opening leave detail. | CONFIRMED-CODE (emulator does not enforce indexes) | Index added. |
| M6 | Medium | A profile with an unknown/missing/lowercase `role` or `status` threw inside `fromWireValue` ⇒ tenant error ⇒ endless splash/retry (no explicit state). | CONFIRMED-CODE + unit test | `InvalidProfileException` → `/account-inactive` "account isn't set up correctly". |
| M7 | Medium | **Data prerequisites are invisible when missing.** Teacher needs `users.branchId`, `staff.userId`, `teacherAssignments`, slots; parent needs `linkedParentId`, portal-enabled `parentLinks`, a *current* `parentAccess`. Any gap ⇒ `permission-denied` or an empty screen with no cause. | CONFIRMED-TEST (profile/branch/index cases) | `diagnoseAccess` Cloud Function + **Check access** in the Login Access dialog names each missing piece and the fix. |
| M8 | Medium | Class-/section-scoped **notices and announcements** (`CLASS`, `SECTION`, homework/result notices) are readable by **any** parent with a family index in the branch; class filtering is client-side. Homework/result notice titles can reveal other classes' activity. | CONFIRMED-CODE | Not changed (needs per-class queries). Plan §6.2. |
| M9 | Medium | Teachers read **all students/parents of their branch**, not only assigned classes (brief asks for assigned-only). `canViewStudentData` is branch-wide by design (attendance, messaging, roster need it). | CONFIRMED-CODE | Not changed. Plan §6.3 (`teacherAccess` index). |
| L1 | Low | Authenticated user with no profile is routed to `/create-school` (needed for self-signup); an invited teacher who signs in with a different Google account lands there too. | CONFIRMED-CODE | Documented; `diagnoseAccess` covers "PROFILE_EXISTS". |
| L2 | Low | Duplicate `match /notifications/{id}` blocks (same path, three places). Harmless (rules are OR-ed) but easy to mis-edit. | CONFIRMED-CODE | Left. |
| L3 | Low | Cross-school isolation relies on every rule comparing the profile's `schoolId` to the path; a legacy document missing `schoolId` fails *closed* (rule error ⇒ deny). | CONFIRMED-CODE | None needed. |

Positive findings (verified by existing + new tests): default deny at the end of the file; no `if true`; users cannot edit `role/schoolId/branchId/status/login`, cannot create a profile with `login`, cannot link themselves to a child or change `parentAccess`; teachers cannot create/alter assignments; parents cannot read other parents/students or list students; cross-school reads/writes denied; Storage rules mirror the same checks with the 2-lookup limit documented.

## 4. Root-cause matrix (Teacher & Parent)

`UID` = authenticated uid; ops are the ones the app issues (same constraints as the Dart repositories).

| Role | Operation (path · op · constraints) | Needed relationship | Before | Root cause | Fix · regression test |
|---|---|---|---|---|---|
| Teacher | `…/teacherAssignments` · list · `academicYearId`,`status==ACTIVE` | same-branch teacher | **denied** | H2 — rule needed owner/manager | rule · `T1` |
| Teacher | `…/attendanceSessions/{dk__y__c__s}` · get (missing) | class-teacher slot | **denied** | H3 — null `resource` | rule · `M1` |
| Teacher | `…/marksSheets/{exam__subj__sec}` · get (missing) | subject slot | **denied** | H3 | rule · `M2` |
| Teacher | `…/homeworkSubmissions/{hw__stu}` · get (missing) | owns homework | **denied** | H3 | rule · `M3` |
| Teacher | `…/staff` · list (homework form) | — (private) | denied | M4 — client asked for colleagues | client · `T2` |
| Teacher | `collectionGroup(parentLinks)` · `schoolId`,`parentId` | branch scope | denied | M2 — branch not pinned | client+index · `T3` |
| Teacher | any branch read with `users.branchId` null/other | profile branch | denied | M7 — data | `diagnoseAccess` · tests "no branchId", "wrong branch" |
| Parent | `…/announcements`/`broadcastNotices` · list · 5 audiences | `parentAccess/{linkedParentId}` | **denied if index missing** | H4 | client fallback · `CONFIRMED:` test + Dart unit test |
| Parent | `…/homeworkSubmissions/{hw__child}` · get (missing) | portal link | **denied** | H3 | rule · `M3` |
| Parent | `…/resultSummaries/{exam__child__vN}` · get (missing) | portal link + PUBLISHED | **denied** | H3 | rule · `M4` |
| Parent | `…/payments` · list · `invoiceId` | own child | **denied** | M1 | client · `P4` |
| Parent | `…/academicYears` · list (leave form) | — | denied | M3 | rule (single get) + client · `P5` |
| Parent | everything under child | `linkedParentId`, portal-enabled link, `parentAccess` | denied when missing | M7 — data | `diagnoseAccess` |
| Both | stale / different live rules | — | any | C1 | VERIFY §7 |

Failing-operation inventory for production (UID, school, error text, path) cannot be produced here: no logs were available. Use **Check access** (Login Access dialog) for any reported UID — it returns the exact missing prerequisite; the app console/Functions logs show the failing path in the `permission-denied` message.

## 5. What changed

See §9 *Modified files*. Highlights: 5 rule edits (+ 1 helper block), 2 indexes, 8 client query/provider changes, 1 new Cloud Function (`diagnoseAccess`), `InvalidProfileException`, tests.

## 6. Recommended migration plan (not implemented — needs product decisions)

1. **H1 Platform admin.** Remove `PLATFORM_ADMIN` from `staffScope`/`isSchoolAdminOrAbove`; keep it for `/users` and platform collections; add an audited callable `supportAccess(schoolId)` that issues a time-boxed `supportGrant` doc the rules honour. Needs a platform-admin UI.
2. **M8 Class-scoped notices.** Parent queries become one query per class/section key (read `parentAccess` first): `audienceKind==CLASS && classId==k`, `SECTION && sectionKey==k`, plus `ALL/BRANCH/PARENTS`. Rules then require `parentHasClass/Section(resource.data…)`. Needs `broadcastNotices.sectionKey` + backfill.
3. **M9 Teacher scope.** Maintain `teacherAccess/{staffId}` (`classKeys`, `sectionKeys`) like `parentAccess` (written by the assignment batch/function); change `canViewStudentData` for TEACHER to require it and make teacher queries class/section-pinned. Large; do after 1–2.
4. Consolidate the three `notifications` match blocks.

Rollout of what *is* implemented is backward compatible: rules only get more permissive for the exact cases above (teachers: ACTIVE assignments; families: one `academicYears/{id}`; missing-doc `get` for people who could create the doc) and never for other roles/schools.

## 7. Deployment, verification and rollback

**Before deploying — confirm the project and compare live rules (C1):**

```
firebase use --add            # or pass --project every time
firebase projects:list
# live vs repo (Rules API); a diff here explains stale-rule symptoms:
firebase deploy --only firestore:rules --dry-run --project <id>
```
Dev = `eazy-school-360-dev`, prod = `eazy-school-360-prod` (see `docs/firebase-environment-configuration.md`). Do dev first, run the manual checks below, then prod.

**Order:** (1) `firebase deploy --only firestore:indexes` (indexes build asynchronously — wait until *Enabled*), (2) `--only functions` (adds `diagnoseAccess`), (3) `--only firestore:rules,storage`, (4) release the app build. Rules first is also safe: the app fallbacks only add queries.

**Smoke test per role after deploy:** teacher — Announcements, Homework → New, Attendance (a day with no register yet), Exams → marks for an assigned subject; parent — Announcements, My homework (unsubmitted item), My results, My fees → invoice, My leave → Apply. Admin — Staff/Parents/Students/Fees/Attendance unchanged. For any failure: Login Access → **Check access**.

**Rollback:** `git revert` the commit(s) and redeploy rules (`firebase deploy --only firestore:rules`), or in the console *Firestore → Rules → History* re-publish the previous ruleset. Indexes are additive and can stay. No data is migrated or deleted by this change. **Never** deploy temporary permissive rules.

**Security of the new function:** `diagnoseAccess` is read-only, requires an ACTIVE admin of the school (same gate as `setLoginAccess`), refuses users of other schools, returns no secrets/PII beyond role and missing-prerequisite text.

## 8. Regression risks and testing strategy

* Missing-document rules now build field maps from ids: a malformed id errors ⇒ **deny** (fail-closed). Tests cover well-formed ids for allowed/denied callers.
* `teacherAssignments` is now broader for teachers: only `status == ACTIVE` documents of their own branch; ENDED history of colleagues stays private (tested).
* Parent `academicYears` `get` requires a `parentAccess` doc (`parentInBranch`).
* `PaymentRepository.watchInvoicePayments` and `ParentRepository.getChildrenForParent` gained optional parameters (fakes updated).
* Ruleset size grew ~3 KB: re-check release.

Automated: `cd functions && npm test` (47 tests: access, OTP, diagnose, push, provisioning); rules emulator suite (327 tests, incl. `login-access-rules`, `rbac-first-load`); `flutter analyze`, `dart format`, `flutter test` (see §9 for the run).

## 9. Results of this audit run and modified files

Executed on 2026-10-15 in the sandbox:

| Suite | Result |
|---|---|
| `flutter analyze` | no issues |
| `dart format --set-exit-if-changed` | clean |
| `flutter test` | **1134 passed, 0 failed** |
| `functions` `npm test` | **47 passed, 0 failed** |
| Firestore + Storage rules (emulator, `--project demo-eazy-school-360`) | **327 passed, 0 failed** (includes 23 new `rbac-first-load` tests and the updated `staff-rules` test) |

Not executed (needs credentials / external systems): live-rules diff, live data checks, deploys, real FCM/Meta delivery, Storage (bucket not enabled).

### Modified / added files

| File | Why |
|---|---|
| `firestore.rules` | H2 (`teacherAssignments`), H3 (missing-doc helpers + 4 rules), M3 (`academicYears` get vs list) |
| `firestore.indexes.json` | M2 `parentLinks (schoolId, branchId, parentId)`, M5 `leaveHistory (subjectKind, subjectId, applicationId, revision)` |
| `firestore-tests/rbac-first-load.test.mjs` (new) | 23 first-load / regression tests for teacher & parent |
| `firestore-tests/staff-rules.test.mjs` | assignment visibility test updated to the new policy |
| `functions/diagnose.js`, `diagnose.test.js`, `index.js`, `access.js` | M7 `diagnoseAccess`; `uid` in `getLoginAccess` |
| `lib/features/announcements/domain/audience_fallback.dart`, `data/firebase_announcement_repository.dart` | H4 |
| `lib/features/fees/**` (repository interface, impl, provider, invoice page) | M1 |
| `lib/features/students/**` (parent repository + profile page/provider) | M2 |
| `lib/features/leave/presentation/pages/leave_apply_pages.dart`, `academic_structure_providers.dart` | M3 |
| `lib/features/homework/presentation/providers/homework_options.dart` | M4 |
| `lib/features/users/domain/user_profile.dart`, `lib/core/tenant/*`, `account_inactive_page.dart` | M6 |
| `lib/features/users/**` login-access dialog/repository/domain | M7 UI (**Check access**) |
| `test/auth/*`, `test/widget/login_access_ui_test.dart`, `test/widget/leave_ui_test.dart`, `test/support/*` | tests / fakes |
| `docs/security/*`, `tool/gen_permission_matrix.py` | documentation |

## 10. Remaining blockers / open items

1. **C1 — verify live rules** against the repo on dev and prod (needs Firebase access). Until then no claim can be made that production behaves like the emulator.
2. Live-data prerequisites (M7) must be checked per affected user with **Check access** after deploying the function.
3. H1, M8, M9 are design changes awaiting a decision (see §6).
4. Meta/WhatsApp setup for phone sign-in is a separate manual task (`docs/authentication-access-management.md`).
5. Not testable here: Firebase Storage (bucket not enabled on dev/prod), real FCM delivery, App Check.
