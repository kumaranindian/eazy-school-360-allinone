# Firestore Architecture

Milestone 0 established the strategy; Milestone 1 implemented its first
real collections (`/users`, `/schools`, `/schools/{schoolId}/branches`);
Milestone 2 added the academic structure nested under a branch
(`academicYears`, `classes`, `sections`, `subjects`, `classSubjects`,
`holidays`, `settings`) — see `docs/milestone-2-school-setup.md`; Milestone
3 adds `students` (+ nested `academicRecords`, `parentLinks`) and `parents`,
also nested under a branch but deliberately NOT under an academic year —
see `docs/milestone-3-student-parent-management.md` for that collection
tree, its relationships, and query/index notes in full detail. Business
collections beyond master data (fees, attendance, leave, ...) still don't
exist — see PROJECT_ARCHITECTURE.md "Known limitations". This document is
what every future collection must follow; `MULTI_TENANT_GUIDE.md` covers
the tenant/role/permission model these collections serve, in more depth.

## Multi-tenancy model

The platform is multi-school and multi-branch. Every document that belongs
to a tenant — which will be nearly everything once business features exist
— must carry:

```
schoolId: string   // required on every tenant-owned document
branchId: string   // required once branch-level scoping applies to that collection
```

Field name constants live in `lib/core/constants/firestore_fields.dart`
(`FirestoreFields.schoolId`, `.branchId`, ...) — never spell these out as
raw string literals in feature code.

**Why `schoolId`/`branchId` as document fields, not separate per-tenant
databases:** a single Firestore database with tenant fields + matching
security rules + composite indexes scales to many tenants without the
operational overhead of provisioning a database per school, and still lets
rules enforce isolation per-document rather than per-database. Revisit this
only if a specific tenant requires physical data isolation (e.g. a
regulatory requirement) — that would be a deliberate exception, not the
default.

## Audit fields

Every tenant-owned document also carries:

```
createdAt: Timestamp
updatedAt: Timestamp
createdBy: string   // uid
updatedBy: string   // uid
```

Also centralized in `FirestoreFields`. Write these via a single repository
helper once the first real collection lands, rather than letting each
feature set timestamps by hand.

## Current collection shape

```
/users/{uid}                                 ← flat — see "Why /users is flat" below
/schools/{schoolId}
/schools/{schoolId}/branches/{branchId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}        ← Milestone 2
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}/sections/{sectionId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}/classSubjects/{subjectId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/subjects/{subjectId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/holidays/{holidayId}
/schools/{schoolId}/branches/{branchId}/settings/workingDays           ← Milestone 2
/schools/{schoolId}/branches/{branchId}/settings/academic              ← Milestone 2
/schools/{schoolId}/branches/{branchId}/students/{studentId}           ← Milestone 3
/schools/{schoolId}/branches/{branchId}/students/{studentId}/academicRecords/{recordId}
/schools/{schoolId}/branches/{branchId}/students/{studentId}/parentLinks/{parentId}
/schools/{schoolId}/branches/{branchId}/parents/{parentId}             ← Milestone 3
/schools/{schoolId}/branches/{branchId}/staff/{staffId}                ← Milestone 4
/schools/{schoolId}/branches/{branchId}/staff/{staffId}/documents/{documentId}
/schools/{schoolId}/branches/{branchId}/staffCodes/{codeLower}         ← employee-code reservation
/schools/{schoolId}/branches/{branchId}/departments/{codeLower}
/schools/{schoolId}/branches/{branchId}/designations/{codeLower}
/schools/{schoolId}/branches/{branchId}/teacherAssignments/{assignmentId}
/schools/{schoolId}/branches/{branchId}/assignmentSlots/{slotKey}      ← active-assignment reservation
/schools/{schoolId}/branches/{branchId}/studentAttendance/{dateKey_studentId}   ← Milestone 5
/schools/{schoolId}/branches/{branchId}/studentAttendance/{id}/history/{revision}
/schools/{schoolId}/branches/{branchId}/attendanceSessions/{dateKey__year__class__section}
/schools/{schoolId}/branches/{branchId}/staffAttendance/{dateKey_staffId}
/schools/{schoolId}/branches/{branchId}/staffAttendance/{id}/history/{revision}
/schools/{schoolId}/branches/{branchId}/staffAttendanceDays/{dateKey}
...
```

The Milestone 2 tree is nested under `branches/{branchId}`, not flat like
`/users` — classes/subjects/holidays don't have the "which tenant am I"
bootstrapping problem a signed-in client's own profile does (by the time
a class query runs, the caller already has `schoolId`/`branchId` from
`TenantContext`), so the default "nest under the owning branch" pattern
applies without the `/users` exception. Full detail, including why
`academicYears`/`classes`/`sections`/`subjects`/`holidays` nest the way
they do relative to each other: `docs/milestone-2-school-setup.md`.

`students`/`parents` nest under `branches/{branchId}` directly —
deliberately NOT under `academicYears/{yearId}` the way classes/sections/
subjects do. A student's identity outlives any single academic year (the
whole point of Milestone 3's "never overwrite history" requirement), so
nesting it under one year's path would make the id itself year-scoped,
which is wrong. `academicRecords` (the actual year-by-year placement
history) and `parentLinks` (guardians) nest under the *student*, not the
year — see `docs/milestone-3-student-parent-management.md` for the full
reasoning, including why `Student.currentClassId`/`currentSectionId` is a
read-optimization cache, not the source of truth.

`staff` nests under `branches/{branchId}` for the same reason students do
(a person's identity outlives any academic year). `teacherAssignments`
sit flat under the branch — *not* under `academicYears/{yearId}` — with
`academicYearId` as a field, so "everything this teacher has ever taught"
is a single query across years while each row is still year-scoped.
Three collections exist purely so **uniqueness is enforced by the
database rather than by a racy client check**, which Firestore rules
cannot otherwise express (rules cannot query): `staffCodes` (id = the
lower-cased employee code), `departments`/`designations` (id = the
lower-cased code, so the code *is* the key), and `assignmentSlots` (id =
`year__class__section__subject|CLASS_TEACHER`). In each, a second `create`
on an existing id is an update, which the rules deny. Full detail:
`docs/milestone-4-staff-teacher-management.md`.

Attendance (Milestone 5) is branch-scoped and keyed for **uniqueness by
document id**: `studentAttendance/{dateKey}_{studentId}` and
`staffAttendance/{dateKey}_{staffId}` mean a person has at most one record
per date, so duplicates from double-clicks, retries or concurrent users are
structurally impossible. Dates are stored as a `yyyy-MM-dd` string
(`dateKey`, used for ids, equality and range queries — a civil date with no
timezone arithmetic) plus a UTC-midnight `Timestamp`. Each record carries an
integer `revision` (rules force +1 per change) that the save transaction
compares to detect concurrent edits, an immutable placement snapshot
(year/class/section/academic record, so a transfer never rewrites history),
and a `history` subcollection written in the same transaction. A register
document (`attendanceSessions`, `staffAttendanceDays`) holds DRAFT/FINALIZED
state and maintained counts so dashboards read one document per section.
Full detail: `docs/milestone-5-attendance-management.md`.

### Why `/users` is flat, not nested under `/schools/{schoolId}`

Milestone 0's version of this document sketched `/schools/{schoolId}/users/{uid}`
as an *illustrative, not-yet-built* example, reasoning that nesting gets
tenant scoping "for free" from the path. Building it for real surfaced the
problem with that: a client has to discover its OWN `schoolId` at sign-in
time, before it can construct any path that starts with
`/schools/{schoolId}/...` — a nested `/users` collection makes that
impossible to query without already knowing the answer.

`/users/{uid}` is flat instead, keyed by the Firebase Auth uid directly.
Firestore rules allow a signed-in user to always read their own
`/users/{request.auth.uid}` document regardless of its `schoolId` — that
single, narrow exception is what makes "who am I, and what school do I
belong to" answerable at all. Every *other* collection (`/schools`,
`/schools/{schoolId}/branches`, and future business collections) is
scoped by the caller's `schoolId` looked up from that same document — see
"Security rules" below.

Future business collections (students, fees, ...) should default to
nesting under `/schools/{schoolId}/...` (optionally
`/schools/{schoolId}/branches/{branchId}/...` if branch-scoped) — that
bootstrapping problem doesn't apply to them, since by the time a feature
queries students, it already has the caller's `schoolId` from
`TenantContext`. `/users` is the one deliberate exception, not the
pattern to copy.

## Query & index discipline (for future features)

- Never fetch a whole collection to filter client-side when a Firestore
  `where()` query can do it.
- Any collection that can grow unbounded needs pagination from day one, not
  "load everything then add paging later."
- A composite query (e.g. `schoolId` + a sort field) needs a matching
  composite index — add it to `firestore.indexes.json` rather than
  discovering the missing-index error in production. `firestore.indexes.json`
  now exists (Milestone 3): 4 composite indexes on `students`/`parents`
  (status/placement filters combined with the `displayNameLower` sort
  used for pagination) and one collection-group index on `parentLinks`
  (`schoolId` + `parentId`, for `ParentRepository.getChildrenForParent`'s
  `collectionGroup()` query) — each with its rationale commented in that
  file. Every Student/Parent list query is cursor-paginated
  (`PagedResult<T>`, `.limit(pageSize + 1)` + `startAfterDocument`) —
  never an unbounded fetch; see
  `docs/milestone-3-student-parent-management.md` → "Queries and indexes".
- Milestone 4 adds 5 composite indexes on `staff` (one per filterable
  field — `status`, `isTeacher`, `departmentId`, `designationId`,
  `employmentType` — each paired with `displayNameLower`; Firestore merges
  them when several filters combine, so the combinatorial set is not
  needed) and one on `teacherAssignments` (`teacherStaffId`, `startDate`
  desc). Staff search is a bounded prefix range on a single normalized
  field (`displayNameLower`, `employeeCodeLower`, `phone`, `emailLower`).
  The teacher list resolves a page of teachers' assignments with one
  `whereIn` query per 30 teachers, not one per teacher.
- Milestone 5 adds composite indexes on `studentAttendance` (year, class,
  section, `dateKey`) and (`studentId`, `dateKey`), on `staffAttendance`
  (`staffId`, `dateKey`), and a **collection-group** index on
  `academicRecords` (school, branch, year, class, section) for the class
  roster. A class register costs N + 1 reads and writes only the changed
  records (2 writes each) plus the register document; reports are capped at
  4,000 records per query.
- Avoid N+1 per-item fetches in a loop; batch-read or restructure the
  query. (`getChildrenForParent` is a deliberate, documented exception —
  see that method's doc comment for why a per-link `get()` was chosen
  over denormalizing a student list onto `Parent`.)

## School creation — a worked example of the batch rule below

`FirebaseSchoolRepository.createSchoolForCurrentUser` (self-serve: a
brand-new account becomes a new school's `SCHOOL_ADMIN`) writes three
documents in **one atomic `WriteBatch`**:

1. `/schools/{schoolId}`
2. `/users/{uid}` — role `SCHOOL_ADMIN`, pointing at that school
3. `/schools/{schoolId}/branches/main` — the default branch

All three exist or none do. `firestore.rules` cross-checks the three
writes using `getAfter()`/`existsAfter()`, which evaluate against the state
the batch *would* produce (plain `get()`/`exists()` see the state before
it). The profile write is only allowed if the same batch creates a school
that did not previously exist and whose `createdBy` is the caller — so a
new account can never attach itself to an *existing* school, and can't
create a profile pointing at a school that was never created.

> Correction (validation audit): an earlier version of this document said
> Firestore rules cannot see other writes in the same batch, and used a
> two-phase write because of it. That was wrong — `getAfter()` exists — and
> the two-phase design left a real hole (see
> `docs/eazyschool360-implementation-report.html`, finding SEC-01).

Accounts created under the old two-phase flow may have a profile but no
default branch; calling the method again repairs that by creating only the
missing branch (allowed because the caller is by then an active
`SCHOOL_ADMIN`).

## Transactions & batch writes

Any operation that must update multiple documents atomically (e.g. any
write that touches both a business document and its audit trail) uses a
Firestore transaction or batch write — not sequential unguarded writes
that can partially fail. School creation above is the template: when
documents only make sense together, write them in one batch and have the
rules for each write verify the others via `getAfter()`.

Milestone 3 has two more examples, both in `FirebaseStudentRepository`:
`admitStudent` batches the new `Student` document with its first
`academicRecords` document (a student is never left existing without an
enrollment, or vice versa); `transferStudent` batches closing the
previous active `academicRecords` document, creating the new one, and
updating the student's current-placement cache — all three or none.
Neither needs `getAfter()` cross-checks the way self-signup does, since
both batches are same-collection-family writes by an already-authorized
caller, not a brand-new, not-yet-profiled account creating its own
authorization.

## Listener lifecycle

Every Firestore stream subscription a feature opens must be cancelled when
no longer needed (widget dispose / provider dispose). A leaked listener
keeps charging reads and can push updates into disposed state.

## Offline behavior

Firestore's offline persistence is available but not yet explicitly
configured or relied upon by any feature. Decide this deliberately per
feature (e.g. "Attendance should work offline and sync later" is a real
product decision) rather than inheriting default behavior silently.

## Security rules

`firestore.rules` enforces real tenant isolation for `/users`, `/schools`,
`/schools/{schoolId}/branches`, the full academic structure nested under
each branch (Milestone 2), `students`/`parents` and their nested
collections (Milestone 3), and `staff`, `staffCodes`, `departments`,
`designations`, `teacherAssignments`, `assignmentSlots` and staff documents
(Milestone 4), and `studentAttendance`, `attendanceSessions`, `staffAttendance`,
`staffAttendanceDays` with their `history` entries (Milestone 5), all using the same lookup-table pattern
(`get()` on the caller's own `/users/{uid}` profile) — see
`MULTI_TENANT_GUIDE.md` → "Security rules" for the full design,
`docs/milestone-2-school-setup.md`/`docs/milestone-3-student-parent-management.md`
for each milestone's rule additions specifically, and `SECURITY_ARCHITECTURE.md`
for why lookup rules were chosen over Firebase Auth custom claims.
Milestone 3 adds one more authorization shape beyond the manage/view
split: `canAccessAsParent`, which checks a *specific relationship record*
(an ACTIVE, portal-enabled `parentLinks` entry naming the caller) rather
than a role-wide grant — a `PARENT` never gets a general "read students"
permission. `storage.rules` now has five real rules (school logo, student photo,
parent photo — Milestone 2/3; staff photo and staff documents — Milestone
4) and otherwise still default-denies everything. Every future collection must add its own
`match` block following the same pattern; the fallback rule at the bottom
of `firestore.rules` default-denies anything not explicitly matched, so a
forgotten rule fails closed.

## Environment separation

Each environment (`dev`/`test`/`uat`/`prod`) is expected to be a **separate
Firebase project**, not a shared project with environment-prefixed
collections. This avoids a dev bug ever being able to touch prod data, and
keeps security rules identical across environments (no "if dev, allow more"
branches in rules). See `DEVELOPMENT_GUIDE.md` for how each environment's
project is wired via `flutterfire configure`.

## Fees (Milestone 6)
Branch-scoped collections: `feeStructures`, `feeAssignments`, `invoices`, `invoiceNumbers`, `feeCounters`, `feeCharges`, `invoiceWaivers`, `payments`, `receipts`, `receiptNumbers`, `paymentReversals`, `financialAudit`. Money is integer minor units. Deterministic ids give idempotency; counter + reservation docs give unique numbers. 15 new indexes. See `docs/milestone-6-fees-management.md`.

## Leave (Milestone 7)
Branch-scoped collections: `leaveTypes`, `leaveApplications` (private), `leaveHistory` (append-only), `leaveCalendar` (minimal public face of approved leave), `leaveDayLocks` (overlap guard), `leaveBalances`, `leaveLedger` (append-only), `leaveSettings/policy`, `notifications`. Leave is counted in half-day integer units; dates are civil `yyyy-MM-dd` keys plus UTC-midnight timestamps; leave year = academic year. Deterministic ids give idempotency (consume/restore ledger ids, history `{app}__{rev}`, notification ids). 26 new indexes. See `docs/milestone-7-leave-management.md`.

## Timetable & substitution (Milestone 8)
Branch-scoped collections: `periodSets`, `timetables` (versioned, `{year}__{class}__{section}__v{n}`), `timetableEntries` (one per weekday + slot, with copied times and display names), `timetableCounters`, `timetableLocks/branch` (publication lock), `timetableHistory` (append-only), `substitutions` (id = `{date}__{timetable}__{slot}`), `substitutionDays` (per-date sequence), `substitutionHistory`. Times are minutes since school-local midnight; dates are civil keys. 5 new indexes. See `docs/milestone-8-timetable-substitution.md`.

## Homework, submissions & announcements (Milestone 9)
Branch-scoped collections: `homework` (id `{batchId}__{sectionId}`, so a retry cannot duplicate), `homeworkHistory` (`{homeworkId}__{revision}`), `homeworkSubmissions` (`{homeworkId}__{studentId}`), `homeworkRevisions` (`{submissionId}__{revision}`, append-only), `announcements`, `announcementHistory`, `broadcastNotices` (`{refId}__{EVENT}__{revision}`, one per event, resolved on read by audience). `users/{uid}/noticeReads/state` holds a user's read state. Targeted `HOMEWORK_RETURNED`/`HOMEWORK_GRADED` notices reuse `notifications`. `homework.dueAt` is the deadline instant the rules compare with the server clock. 14 new indexes. See `docs/milestone-9-homework-assignments-announcements.md`.
## Examinations, marks & results (Milestone 10)
Branch-scoped: `gradingSchemes`, `examinations` (id `{year}__{class}__{section|ALL}__{slug}`), `examinationSubjects` (`{examId}__{subjectId}`), `examHistory`, `marksSheets` (`{examId}__{subjectId}__{sectionId}`), `marksSheetHistory`, `marksEntries` (`{sheetId}__{studentId}`), `marksRevisions`, `examRemarks`, `resultSummaries` (`{examId}__{studentId}__v{n}`, create-only, with the scheme snapshot). Counters on the examination (`subjectCount`, `sheetCount`, `approvedSheets`, `resultVersion`, `resultCount`, `resultsWritten`) move in the same commit as the documents they count. 5 new indexes. See `docs/milestone-10-examinations-results-report-cards.md`.

## Notifications & conversations (Milestone 11)
Branch-scoped: `conversations` (id `cv_…`; `participants` = parent + teacher; per-member unread counters, status, revision, flag), `conversations/{id}/messages` (create-only), `conversationEvents` (`{conversationId}__{revision}`, append-only), `messageContacts/{staffId}` (teacher opt-in + where they teach). User-scoped: `users/{uid}/preferences/notifications`. New `MESSAGE_RECEIVED` notices use the existing `notifications` collection (id `msg__{messageId}`). Indexes: `conversations(participants, lastMessageAt↓)`, `messageContacts(enabled, sectionKeys)`.

## Family access index (Milestone 12A)
`branches/{b}/parentAccess/{parentId}`: `classKeys` (`classId`) and `sectionKeys` (`classId__sectionId`) of the family's ACTIVE, placed children behind ACTIVE portal-enabled links. Derived data, rewritten by staff-side writes (link/transfer/status change) and the *Refresh parent access* action; read by rules to scope parents to class-specific homework, schedules and examinations. Missing document = no class-specific access. Index: `examinations(academicYearId, classId, status, sectionId)`.
