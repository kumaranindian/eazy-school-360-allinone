# Firestore rules audit & rewrite — status report (2026-10-15)

Companion to `rbac-audit.md` (findings), `role-permission-matrix.md` (roles) and `firestore-collection-inventory.md` (generated, every match block).

## Decision: harden and restructure, not rewrite from scratch — and why

The repository's `firestore.rules` (≈3.8 k lines) already has one authorization architecture: a lookup of the caller's `/users/{uid}` profile (`activeAndAllowed`, `staffScope`, `isFamilyCaller`, …), relationship records (`staff.userId`, `assignmentSlots`, `parentLinks`, `parentAccess`) and per-collection write plans replayed by *contract tests*. It is covered by **361 emulator tests** (positive and negative). A from-scratch rewrite would have to re-derive the fee, leave, timetable, exam and homework write rules (hundreds of `getAfter` transaction checks) and would be judged only by those same tests; the security upside is nil and the regression risk is real. What was wrong was **specific**, found by tracing every screen's queries against the rules, and fixed at its root. If you still want the file physically re-authored, that is a mechanical follow-up the tests can validate; I did not do it blindly.

Backup of the pre-change file: git history (`git show 8614984:firestore.rules`); nothing was deleted.

## Evidence that the repository rules now serve Teacher and Parent

`firestore-tests/rbac-screen-sweep.test.mjs` runs **every Firestore read a Teacher or Parent screen issues** (same collection, `where`/`orderBy`, collection-group and aggregate shape as the Dart repositories; 34 tests) with healthy data. All pass. `rbac-first-load.test.mjs` (23) covers the failure modes: missing profile fields, wrong branch, missing parent index, missing-document reads, unpinned queries. Together with the earlier fixes (`rbac-audit.md` H2–H4, M1–M5) this means: **with the repository rules and healthy data, no teacher/parent screen is denied.** Remaining production denials therefore come from (a) deployed rules differing from the repository (audit C1), or (b) missing relationship data (audit M7 — use *Check access*).

## This pass: changes

| Change | Why |
|---|---|
| New `rbac-screen-sweep.test.mjs` (34 tests) | Systematic root-cause sweep instead of one-off fixes |
| Removed unused helper `isHomeworkTeacherOrAdmin` | Dead code (the only unused helper of 145) |
| `tool/gen_rules_inventory.py` + generated inventory | Complete, reproducible collection × operation inventory |
| Cross-check Dart ↔ rules | Every collection the app or functions touch has a rule; `devices`, `noticeReads`, `preferences` are matched under `/users/{uid}/…`; `authSettings`, `authAudit` are server-written |
| Intentional overlap documented | `notifications` has three `match` blocks on purpose (expression-budget headroom): the first owns read/update, the others only add narrow `create` types; they cannot widen read/update |

(Earlier today: ACTIVE-assignment read for teachers, missing-document `get` rules for 4 collections, single `academicYears` get for families, parent announcement fallback, payments/parentLinks query pinning, two indexes, `diagnoseAccess`, `InvalidProfileException`.)

## Role × collection summary

See `role-permission-matrix.md` (data access table) and the generated inventory (exact helpers per operation). Roles found in code: `PLATFORM_ADMIN`, `SCHOOL_ADMIN`, `BRANCH_ADMIN`, `FINANCE`, `TEACHER`, `PARENT` — no others exist. Privilege assignment: a school user can never obtain `PLATFORM_ADMIN` (create/update rules list only `schoolAdminManagedRoles`/`branchAdminManagedRoles`; self-sign-up creates `SCHOOL_ADMIN` of a brand-new school only; `login` is server-written).

## Not done / pending decisions (each changes product behaviour)

1. **Teacher scope by assignment (audit M9) — DONE.** Teachers read a student only when its `classId__sectionId` is in their `teacherAccess/{uid}.sectionKeys` (server-written by Cloud Functions from ACTIVE `teacherAssignments`; clients cannot write it). The teacher Students screen lists the teacher's own sections with section-pinned queries. Parents are visible to a teacher only through `parents/{id}` `get` when the parent's `parentAccess.sectionKeys` intersects the teacher's; the teacher parents directory was removed. **Rollout order:** deploy functions → run *Refresh teacher access* (callable `refreshTeacherAccess`, backfills existing assignments) → deploy rules. Known limits: students of a section the teacher no longer holds (historical) are unreadable; non-portal-linked parents are not visible to teachers; Storage student photos remain branch-readable.
2. **Class-scoped notices for parents (M8) — DONE.** `broadcastNotices` / `announcements` for `CLASS` / `SECTION` audiences are readable only when the parent's `parentAccess` contains that class / section (`parentMayReadAudience`). The client issues one general query (`ALL, BRANCH, PARENTS`) plus one pinned query per class / section key in the family's `parentAccess` and merges them (`planScopedParentQueries`, `mergeNewestFirst`; live merged stream for notices). Four new composite indexes — deploy them before the rules.
3. **Platform Admin breadth (H1).** Blanket access to every school's data; the fix needs an audited support-access workflow.
4. **Dev deployment.** Not executed — no Firebase credentials in this environment (`firebase projects:list` → "Failed to authenticate"). The rules compile and load in the emulator (all suites). Commands, run from your machine:
   ```
   git pull origin develop
   firebase use eazy-school-360-dev            # confirm the alias/project
   firebase deploy --only firestore:indexes --project eazy-school-360-dev   # wait until indexes are Enabled
   firebase deploy --only functions --project eazy-school-360-dev
   firebase deploy --only firestore:rules --project eazy-school-360-dev
   ```
   Then smoke-test per role (list in `rbac-audit.md` §7) and use *Check access* for any user who still sees `permission-denied`. Production is a separate step after dev passes.
5. **End-to-end with real accounts** (Phase 12): not possible here.

## Results actually obtained

| Check | Result |
|---|---|
| Firestore + Storage rules emulator suite (`--project demo-eazy-school-360`) | 395 / 395 pass |
| `functions` `npm test` | 67 / 67 pass |
| `flutter analyze` / `dart format` / `flutter test` | clean / clean / 1250 pass |

Note: in this sandbox the emulators must be run with the proxy variables unset (`env -u HTTPS_PROXY -u https_proxy -u JAVA_TOOL_OPTIONS ...`); otherwise Storage→Firestore lookups are blocked by the egress proxy and Storage tests fail spuriously.

Multi-branch (per-branch roles, school-wide years, branch transfers): see `docs/multi-branch.md`.
