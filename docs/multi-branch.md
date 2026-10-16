# Multi-branch support

A school can run several branches. Everything operational (classes, sections, students, attendance, fees, results…) is
**owned by one branch** (`schools/{s}/branches/{b}/…`). This change adds the three things that cut across branches:
staff who work in more than one branch, academic years defined once for the whole school, and moving a student
between branches. Tests: `firestore-tests/multi-branch-*.test.mjs`, `school-year-rules.test.mjs`,
`branch-transfer-contract.test.mjs`; `functions/branch_access.test.js`; `test/core/multi_branch_tenant_test.dart`,
`test/widget/{multi_branch_ui,school_years_ui,student_branch_transfer_ui}_test.dart`.

## 1. Staff in several branches

**Model.** `users/{uid}` keeps its home `branchId` + `role`. Extra branches live in
`branchRoles: { <branchId>: 'TEACHER' | 'FINANCE' | 'BRANCH_ADMIN' }`. Only Cloud Functions write it
(`setBranchAccess`, and `provisionLogins` for the same person in a second branch); clients cannot, not even a school
admin (the `users` rules never list the field). Parents, school admins and platform admins never carry one.

**Rules.** `branchRoleOf(p, branchId)` returns the home role in the home branch, a *valid staff role* from `branchRoles`
elsewhere, otherwise null — so a corrupt value (`SCHOOL_ADMIN`, `PLATFORM_ADMIN`, junk) grants nothing. Every place that
compared `callerBranchId()` / `p.branchId` now uses it (`staffScopeOf`, teacher/section helpers, leave, attendance,
announcements, exam entry, `profileOwnsStaff`, Storage `roleIn`). `teacherAccess/{uid}` is already per branch, so a teacher
in a second branch sees only the sections they are assigned to *there*.

**Setting it up (school admin).**
1. Add the person as active staff in the other branch with the **same email**.
2. *Give login access* in that branch: because the email belongs to a staff login of the same school, the person is
   **linked**, not duplicated — the role chosen is added to `branchRoles`. Branch admins cannot do this (a branch admin
   cannot take over someone else's login); it answers "email in use". Or:
3. Staff → *Login access* → **Other branches**: pick a role per branch (or *No access*) — calls `setBranchAccess`.
   Requires an ACTIVE staff record of that person in the branch.
Every grant/revoke is written to `schools/{s}/branchAccessAudit` (school-admin readable). Deactivating or unlinking the
staff record in a branch removes the role automatically (`staffBranchAccessSync`). Disabling the login (status/`login`)
still blocks every branch at once.

**In the app.** A *branch switcher* appears in the header for anyone who works in more than one branch. Choosing a branch
re-resolves the tenant (role **and** branch), so every screen follows; it lands on the dashboard because the role — and
therefore the menu — can differ. The choice is not remembered across sign-ins (the home branch is used).

**Login access is account-wide.** A branch admin can change login access only for people whose *home* is their branch; a
school admin can for anyone in the school.

**Notifications.** Branch/staff notices and leave-review notifications reach staff by per-branch role too.
`diagnoseAccess` ("Check access") understands per-branch roles.

## 2. School-wide academic years

`schools/{s}/academicYears/{id}` = `{name, startDate, endDate, status ACTIVE|ARCHIVED}` — the **definition** only. Created
by a school admin; immutable except archiving (a typo means: archive it and add the right one).

A branch **opens** a year: that creates `branches/{b}/academicYears/{same id}` (DRAFT, with `schoolYearId`). The rules only
accept a branch year that is the copy of an **ACTIVE** registry year — same id, name and dates — so branches cannot invent
or drift. A branch then activates/closes *its* copy independently (one ACTIVE year per branch, as before); only `status`
changes on a linked year. Classes, sections, subjects, holidays, fees… stay in the branch's year.

* School admin: Settings → Academic years → *School years (all branches)* → add a year, *Open in branches*, archive.
* Branch admin: Settings → Academic years → *Open a school year*.
* **Existing branch-only years keep working and stay editable** (no `schoolYearId`); nothing is migrated. New years must
  come from the registry.

## 3. Moving a student between branches

School admin only: student profile → *Move to another branch*. One atomic batch (`BranchTransferWrites`):
* **New branch:** the student with the same id and a new admission number (`transferredFrom`), already placed in a
  section, plus the guardians (a copy of the parent record under the **same parent id**, so the parent's login keeps
  working) and their links.
* **Old branch:** the record becomes `TRANSFERRED` and points forward (`transferredTo`); its placement is closed. Attendance,
  fees, marks and academic records **stay in the old branch**, readable there — nothing is moved or deleted.
* `schools/{s}/studentTransfers/{id}`: who, when, from/to, admission numbers, reason. Immutable; school-admin readable.
Both sides cross-check each other in the rules (`getAfter`), a moved student cannot be set ACTIVE again in the old branch,
and a second move of the same record is refused. Parents with children in several branches already see them all.
The family's `parentAccess` is refreshed in both branches. To bring a student back, admit them again.

## Rollout (dev, then prod — in this order)
1. **Release the app first.** Old builds can still *create* standalone academic years; after step 4 the rules refuse that.
2. Deploy functions (`setBranchAccess`, `staffBranchAccessSync`, updated `provisionLogins`, recipients, diagnose).
3. For each school: a school admin adds its **school years** and opens the current year in every branch where a branch year
   is still to be created (existing branch years need nothing).
4. Deploy `firestore.rules` and `storage.rules`.
5. Smoke test: a two-branch teacher (switcher, role per branch), a school admin opening a year in two branches, a student
   move and the parent's view of it.
Rollback: redeploy the previous rules; `branchRoles`, registry years and transfer records are inert without them.

## Known limits
* The branch choice is per session (not persisted).
* A student's photo is not carried to the new branch (the file lives in the old branch's Storage folder); re-upload it.
* Fees are not carried over: balances and invoices stay with the old branch; the new branch starts from its own structures.
* There is no bulk transfer or promotion across branches, and no way to undo a move except admitting the student again.
* A registry year's name/dates cannot be edited.
