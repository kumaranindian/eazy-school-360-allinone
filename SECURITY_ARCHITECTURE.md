# Security Architecture

## Core principle: the client never is the enforcement boundary

Hiding a button, disabling a route, or a Flutter-side `if (role == ...)`
check is a usability nicety, not a security control. A corrected client
build, a modified request, or an authenticated `curl` call routes around
client-side checks trivially. The real boundary is:

```
Firebase Authentication   → who is this caller?
Firestore/Storage rules   → what is this caller allowed to read/write, enforced server-side
```

Everything client-side (route guards, disabled buttons, conditional UI) is
UX layered on top of that boundary — never a substitute for it.

## Authentication vs. authorization

- **Authentication**: Firebase Auth — email/password, Google Sign-In,
  forgot/reset password, sign-out, all wired end-to-end through
  `FirebaseAuthRepository` → `authStateChangesProvider` → GoRouter
  redirect. See `lib/features/authentication/`.
- **Authorization**: role/permission checks and tenant isolation, now
  implemented — see "Tenant isolation" and "Authorization model" below,
  and `MULTI_TENANT_GUIDE.md` for the full design.

## Current state of route guarding

`lib/core/routing/app_router.dart`'s `redirect` callback is a full state
machine now (see `MULTI_TENANT_GUIDE.md` → "Authentication flow" for the
diagram): signed-out users are confined to `/login`/`/forgot-password`;
signed-in users with no profile yet go to `/create-school`; signed-in
users whose profile is not `ACTIVE` go to `/account-inactive`; everyone else
reaches the authenticated shell. `AppShell`
(`core/routing/app_shell.dart`) additionally filters navigation
destinations by `TenantContext.can(Permission.x)` — a role losing a
permission immediately loses the matching nav item.

**This remains a UX layer, not the enforcement boundary** — see the
section at the top of this document. The actual guarantee is
`firestore.rules`, described next.

## Authorization model

- **Roles** (`core/permissions/user_role.dart`): `PLATFORM_ADMIN`,
  `SCHOOL_ADMIN`, `BRANCH_ADMIN`, `TEACHER`, `FINANCE`, `PARENT`.
- **Permissions** (`core/permissions/permission.dart` +
  `role_permissions.dart`): a fine-grained capability set, with a single
  `RolePermissions.grants` map from role → permissions. UI code calls
  `tenantContext.can(Permission.x)` — nothing hardcodes `role == ...`
  checks. This is the "centralized authorization mechanism" requirement
  made concrete; see `MULTI_TENANT_GUIDE.md` → "How to add a new role".
  Milestone 2 added `manageAcademicSetup` (school/branch/platform admins)
  and `viewAcademicSetup` (also teacher/finance, read-only) — see
  `docs/milestone-2-school-setup.md` → "Permissions" for the full matrix.
  Milestone 3 added the same manage/view pair for student/parent master
  data: `manageStudentData` and `viewStudentData`. `UserRole.parent`
  deliberately holds neither — a parent's access to student data is
  relationship-based, not a role permission; see "Tenant isolation" below
  and `docs/milestone-3-student-parent-management.md` → "Parent data
  security".
  Milestone 5 added `viewAttendance`, `markStudentAttendance`,
  `manageAttendance` and `viewStaffAttendance`; a TEACHER holding
  `markStudentAttendance` can mark only the section they are class teacher
  of (see "Milestone 5: attendance rules" below).
  Milestone 4 added `manageStaff`, `viewStaff` and `viewOwnStaffProfile`.
  Staff authorization is deliberately independent of a person's
  *designation* ("Senior Teacher", "Principal"): a designation is
  descriptive data and appears in no rule or permission; what someone can
  do comes from their linked `/users` account's role. A teacher gets no
  staff-directory access at all — only their own record and their own
  assignments, found through the staff record's `userId` link — and
  finance gets read-only access to staff in their own branch.
- **This is a UX-layer mirror of `firestore.rules`, not a substitute for
  it.** `RolePermissions` controls what the UI *offers*. `firestore.rules`
  independently controls what Firestore *allows*, re-implementing the
  same role boundaries in rules syntax rather than calling into this Dart
  map (rules can't import Dart code). Keeping the two in sync is a
  deliberate, manual step documented in `MULTI_TENANT_GUIDE.md` — there is
  no single source of truth shared across both runtimes, by necessity.

## Tenant isolation

A user in one school must never be able to read or write another school's
data, even by guessing a document ID. This is now enforced in
`firestore.rules` for `/users`, `/schools`, `/schools/{schoolId}/branches`,
every collection nested under a branch (Milestone 2's academic years,
classes, sections, subjects, class-subject links, holidays, and branch
settings; Milestone 3's students, their nested academic records and
parent links, and parents), plus `storage.rules` for the school logo,
student photo, and parent photo paths, all mirroring the same pattern via
`firestore.get()` cross-service lookups. See "Custom claims vs. lookup
rules" below for *how*, and `firestore-tests/rules.test.mjs` /
`storage-rules.test.mjs` for the executable proof (School A vs. School B,
parent-vs-parent, disabled accounts, role-escalation attempts,
cross-branch reads within the same school, Parent A's own child vs.
Parent B's child — 45 tests total, run via the Firestore + Storage
emulators, no real project needed; see `DEVELOPMENT_GUIDE.md`). The
fallback rule at the bottom of `firestore.rules` still default-denies
anything not explicitly matched, so a future collection added without its
own rule block fails closed.

**Parent isolation specifically** (brief §36, Milestone 3) is enforced
by `canAccessAsParent(schoolId, branchId, studentId)`: a `PARENT`-role
caller may read a student only if their own `/users/{uid}.linkedParentId`
names a `parentLinks` entry on *that exact student* with `status ==
'ACTIVE'` and `canAccessPortal == true`. A parent can never browse the
roster, search other families, or read a different parent's contact
record — proven by `"Parent A -> own child ALLOW; Parent A -> child of
Parent B DENY"` and the `canAccessPortal=false` denial test in
`rules.test.mjs`.

**A real bug, not just a hypothetical one, was caught this way during
Milestone 2**: the academic-structure rules were initially nested as
siblings of `branches/{branchId}` instead of children of it — a
copy-paste-adjacent structural mistake that made every Milestone 2
collection fall through to the default-deny fallback (completely
inaccessible, not insecure, but also completely non-functional). The
rules test suite caught it immediately via `permission-denied` errors
pointing at the fallback rule's line number. This is the concrete case
for why "add a test when you add a rule" isn't optional process — see
`docs/milestone-2-school-setup.md` for the full account.

## Custom claims vs. lookup rules

Milestone 0's version of this document anticipated Firebase Auth **custom
claims** (`request.auth.token.role`, `.schoolId`, ...) as the mechanism
for rules to know who's calling. Implementing real tenant isolation
surfaced the actual tradeoff:

- **Custom claims** need a trusted server-side writer — a Cloud Function
  — to issue them, since a client must never be able to set its own
  claims. This project has no Cloud Functions (see Milestone 0's "Cloud
  Functions only when genuinely required," and Milestone 1's brief itself
  never mentions them). Standing up Cloud Functions infrastructure for
  this alone, before any feature needs server-side compute, would be
  exactly the premature infrastructure both milestones' briefs warn
  against.
- **Lookup rules** — what this project uses instead — have every rule
  that needs to know "who is this caller" read the caller's *own*
  `/users/{request.auth.uid}` document via `get()`. No Cloud Function
  needed, and — critically — fully testable right now against the
  Firestore emulator, which is what actually lets this milestone *prove*
  tenant isolation rather than assert it.

The tradeoff: lookup rules cost one extra document read per rule
evaluation (`get()` reads count toward quota), where custom claims are
free (already in the request). At this project's current scale, that's
the right trade. **Revisit this once a feature's read volume makes the
`get()` cost matter**, or once Cloud Functions exist for an unrelated
reason (at which point syncing claims from `/users/{uid}` writes via a
Firestore trigger becomes close to free to add). Don't migrate
speculatively before either is true.

## Why Firebase client config isn't treated as a "secret" — but is still not committed

Firebase's own documentation is explicit that a client app's `apiKey`,
`appId`, and `projectId` are public identifiers, not secrets — they
identify which Firebase project a request is for; they do not themselves
grant access (Firestore/Storage rules do). Despite that, this project
gitignores the generated `firebase_options_<env>.dart` files
(see `lib/core/config/firebase_options/firebase_options.dart.example`) and
keeps `.firebaserc` out of git too, per the brief's explicit instruction not
to hardcode "Firebase project IDs... environment-specific configuration" in
source. The practical effect: every environment's real project identifiers
live only on the machine/CI runner that builds for it, generated on demand
via `flutterfire configure` (see `DEVELOPMENT_GUIDE.md`) — never in commit
history, even though leaking one would not, by itself, grant data access.

What must never be committed, logged, or exposed to a client regardless of
the above: Firebase Admin SDK service-account keys, any server-side-only
credential, and of course anything that actually is a secret (passwords,
session tokens, API keys for third-party paid services).

## Error handling and information disclosure

`core/errors/error_mapper.dart` translates every Firebase exception to a
generic, user-facing `AppFailure` before it reaches the UI
(`"You don't have permission to perform this action."`, not
`"permission-denied: Missing or insufficient permissions."`). Technical
detail is logged via `AppLogger`, not shown to the user — see
`core/logging/app_logger.dart`'s explicit list of what must never be logged
(passwords, tokens, sensitive personal data, payment details).

## Google Sign-In

Implemented in `FirebaseAuthRepository.signInWithGoogle()` — Firebase's
`signInWithPopup` on Web, the `google_sign_in` plugin's token exchange on
Android/iOS. A closed picker/popup is treated as a no-op
(`GoogleSignInCancelled`), not an error.

**This cannot complete a real sign-in yet**, for the same reason nothing
Firebase-backed can: no real Firebase project exists (see
`PROJECT_ARCHITECTURE.md` → "Known limitations"). Once one does, Google
Sign-In additionally needs, per environment:
- **Android**: the app's release/debug SHA-1 and SHA-256 fingerprints
  registered against the Firebase project, and the resulting OAuth client
  downloaded into that environment's `firebase_options_<env>.dart`
  generation (via `flutterfire configure`).
- **iOS**: the reversed-client-ID URL scheme registered in
  `ios/Runner/Info.plist` (`flutterfire configure` / the Google
  Sign-In setup docs generate this) — not yet present in this repo.
- **Web**: no extra setup beyond the Firebase project itself — Firebase's
  own popup flow handles the OAuth exchange.

None of this is fabricated or guessed at — it's genuinely blocked on a
real project existing, consistent with every other "no real Firebase
project yet" limitation in this codebase.

## Input validation

`core/validators/validators.dart` provides client-side validation for
immediate user feedback. This is a UX layer, not the authoritative check —
once business features exist, equivalent validation must also be enforced
in Firestore rules (`request.resource.data` shape checks) for any write a
rule allows, since a modified client can send anything to a reachable
endpoint.

## Known limitations (explicitly deferred)

- **No custom claims** — see "Custom claims vs. lookup rules" above for
  why, and when to revisit it.
- **School status is not enforced** for a school's users (see
  PROJECT_ARCHITECTURE.md → Known limitations).
- **No Cloud Functions** — tenant isolation doesn't need them (see above);
  add them when a feature genuinely requires server-side compute, not
  speculatively.
- **`storage.rules` now has five real rules** (school logo, student
  photo, parent photo, staff photo, staff documents) and otherwise still
  default-denies everything. Staff documents (ID proofs, certificates) are
  readable and writable by managers only — not by same-branch teachers or
  finance — and never deletable; staff photos are the one path that allows
  a delete, for "Remove photo" —
  user profile photos (`UserProfile.photoUrl` is a model field) still have
  no upload UI or rule.
- **No self-service parent portal-access flow.** The authorization
  foundation (`linkedParentId`/`linkedUserId`, the rules that make it
  work) is complete and tested, but creating the actual Firebase Auth
  account for a parent and linking it is still a manual, multi-step admin
  action — see `docs/milestone-3-student-parent-management.md`.

## Milestone 4: staff and teacher rules

Rules added for `staff`, `staffCodes`, `departments`, `designations`,
`teacherAssignments`, `assignmentSlots` and staff `documents` (full design
in `docs/milestone-4-staff-teacher-management.md` → "Security rules"):

- Tenant and branch isolation come from the same `canManage*`/`canView*`
  lookup-table functions as Milestones 2–3, applied to every collection.
- Writes that must stay consistent across documents (a staff record and
  its employee-code reservation; an assignment and its uniqueness slot;
  ending an assignment and releasing its slot) are single batches that the
  rules verify with `existsAfter`/`getAfter`, so a client cannot do half of
  one. This is how duplicate employee codes, a second class teacher for a
  section, and a second teacher for a section + subject are impossible
  rather than merely discouraged.
- An assignment re-verifies every reference server-side: the teacher is an
  `ACTIVE` teacher of the branch, the section exists under that class and
  year and is active, and the subject is linked to that class.
- `schoolId`, `branchId`, `createdAt`, `createdBy` are immutable; audit
  actors must be the caller; resigned/terminated/retired is final.
- Tested in `firestore-tests/staff-rules.test.mjs` and
  `staff-storage-rules.test.mjs` (32 tests, mutation-checked).

## Milestone 5: attendance rules

Full design in `docs/milestone-5-attendance-management.md` → "Security
rules". The pieces that matter for the security model:

- **Teacher scope comes from data, not the role.** `isClassTeacherOf`
  resolves the Milestone 4 `CLASS_TEACHER` assignment slot for the exact
  year/class/section, then that slot's staff record, then requires its
  `userId` to be the caller and the staff member `ACTIVE`. A teacher who is
  class teacher of 5-A cannot write 5-B, and a resigned teacher loses the
  right as soon as their status changes.
- **Finalization is enforced in the rules**, not by hiding a button: once a
  register is `FINALIZED`, student and staff records accept writes only from
  a manager and only with a written reason; history is immutable.
- **Concurrency**: the rules force `revision` to advance by exactly one;
  together with the client's transaction this prevents silent overwrites.
- **Finance** can read staff attendance (payroll groundwork) and nothing
  else; **parents** have no access (a future portal must go through
  `parentLinks`).
- **Deliberate gaps** (no Cloud Functions in this project): the rules do not
  check per-student enrollment, the holiday calendar, or the register
  counts. A class teacher could therefore write a record for a student who
  is not in their section (never another tenant/branch; only for their own
  section's registers), and calendar rules are a client policy. A trusted
  backend operation is the fix if that risk is unacceptable.
- 21 emulator tests in `firestore-tests/attendance-rules.test.mjs`,
  mutation-checked.

## Validation audit (rules hardening)

The M0/M1 validation audit found and fixed these rule defects, each now
covered by a test in `firestore-tests/rules.test.mjs` that fails against
the old rules and passes against the current ones:

| ID | Severity | Defect (old rules) | Fix |
|---|---|---|---|
| SEC-01 | Critical | A new account could create its own profile as `SCHOOL_ADMIN` of any *existing* school | Self-signup must be one batch that also creates the school; checked with `getAfter()` |
| SEC-02 | High | Profiles could point at schools that were never created | Same fix as SEC-01 |
| SEC-03 | High | A `SCHOOL_ADMIN` could change their own school's `status` (e.g. lift a suspension) | School-admin updates limited to profile fields via `diff().affectedKeys().hasOnly(...)` |
| SEC-04 | Medium | `createdBy`/`updatedBy`/timestamps were client-controlled | `createdAt`/`updatedAt == request.time`, actor fields `== request.auth.uid` |
| SEC-05 | Medium | Dart granted `BRANCH_ADMIN` `manageUsers`, but rules gave them no path | Branch-scoped create/update rules for `TEACHER`/`FINANCE`/`PARENT` |

See `docs/eazyschool360-implementation-report.html` for the full audit.

## Fees (Milestone 6)
Admins manage structures/waivers/void/reversal; finance assigns, issues and collects; parents read only linked children's records; teachers have no access. Invoice changes are valid only as PAYMENT/REVERSAL/WAIVER/VOID events tied to their records. Limitation: rules cannot sum invoice lines, and client transactions do not stop a malicious privileged client; use a trusted backend if that matters. See `docs/milestone-6-fees-management.md` §7.

## Leave (Milestone 7)
Reviewers are the admins (`canManageStaff`); applications are private to the applicant, the linked parent / own staff record and reviewers; teachers read only the minimal `leaveCalendar`. Every status change must arrive with its history record; a reviewer cannot decide their own application; a balance moves only with its ledger entry; day-locks make overlaps impossible under concurrency. Supporting documents: applicant-create-only, applicant + reviewing admins read. Limitation: rules cannot verify the counted dates against the holiday calendar or monthly accrual-to-date (they enforce the whole-year ceiling); a trusted backend would be needed for that. A Dart-to-rules contract test replays the Dart-written documents through the real rules. See `docs/milestone-7-leave-management.md` §9.

## Timetable & substitution (Milestone 8)
Managers (admins) create, publish and cover; teachers and parents read PUBLISHED data only. Every change to what is published bumps a branch lock in the same commit, so a validation against an older published set cannot be committed; cells only change while a draft and their teacher must hold the section's ACTIVE assignment slot; a cover is a live cell of a published timetable, one per slot and date. Limits: rules cannot query other timetables, so teacher/room double-booking across timetables is verified by the client under the lock (a trusted backend would be required to prevent a modified client skipping it), and parents cannot be tied to their child's section in rules. See `docs/milestone-8-timetable-substitution.md` §8.

## Homework, submissions & announcements (Milestone 9)
Teachers create/publish homework only for a section+subject whose ACTIVE assignment slot names them; a parent submits only through an ACTIVE, portal-enabled link, for a child currently placed in that class and section; lateness is decided on the server clock; families cannot write marks, feedback or grader fields; every change appends a history/revision document in the same commit; announcements are addressed by authority (class teachers → their section, branch admins → their branch, school admins → everyone). Storage paths are create-only with type/size limits and per-child paths guarded by the parent link. Limits: parents are school-wide *readers* of published homework/announcements (rules cannot look up by child), scheduled announcements cannot be hidden by list rules, Storage rules have a two-lookup budget, and fan-out, reminders, cleanup and malware scanning need a trusted backend. See `docs/milestone-9-homework-assignments-announcements.md` §8.
## Examinations, marks & results (Milestone 10)
Administrators configure, review, finalise and publish; a teacher enters marks only for a section+subject whose ACTIVE assignment slot names them, for enrolled students, while marks entry is open; the approver of a sheet is not its submitter (school admin excepted). Finalised results are create-only and versioned; a correction is withdraw → reopen → new version. Parents read only a linked child's result, only while PUBLISHED and only the version in force. Limits: rules cannot recompute totals/grades or count documents (client calculator + stored scheme snapshot; trusted backend needed), teachers can read published results branch-wide, parents can read published examination configuration school-wide. See `docs/milestone-10-examinations-results-report-cards.md` §9.

## Notifications & parent–teacher conversations (Milestone 11)
A conversation needs a linked ACTIVE parent of an ACTIVE placed child and a teacher who holds the assignment slot for that child's section and has opted in; only the two participants read or post; administrators read only after a member reports (an audited event); messages are never edited or deleted; closed conversations take no messages. Notices carry no message text and are created in the same commit as the message with a deterministic id. Notification navigation never authorises: routes and rules re-check. Storage: participant-only reads, create-only while OPEN. Push is not implemented; no service-account material is in the client.

## Family read scope (Milestone 12A)
Parents read homework, timetables/live entries/substitutions and examinations only for classes/sections where `parentAccess` lists a child; `ALL` announcements stay school-wide; branch-targeted announcements need a child in the branch. Families cannot write the index. Residual: class-targeted announcements are visible within a branch the family has a child in (F-SEC-4). Cutover order and finance back-end threat model: `docs/milestone-12a-blocker-closure.md`.
