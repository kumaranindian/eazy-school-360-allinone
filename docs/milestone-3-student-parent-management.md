# Milestone 3 — Student + Parent Management

This is the Milestone 3 companion to `PROJECT_ARCHITECTURE.md` (overall
layout), `FIRESTORE_ARCHITECTURE.md` (collection design generally), and
`SECURITY_ARCHITECTURE.md` (rules generally) — covering the Student/Parent
master-data module in full: models, relationships, permissions, security
rules, queries/indexes, the admission/transfer/withdrawal flows, and what
was deliberately left out.

## Why this module exists, and what it is not

Student + Parent management is the foundation every later business
feature (Attendance, Fees, Leave, Homework, Exams, the Parent Portal)
will be built against. Getting the *shape* of this data right now — so a
student's academic history is never silently lost when they move class —
matters more than any one screen in this milestone.

This milestone explicitly does **not** implement Staff/Teacher
management, Attendance, Fees, Leave, Homework, advanced notifications,
Payroll, Transport, Exams, Marks, or Report Cards. It also does not
implement the Parent Portal itself (an authenticated parent-facing app) —
only the relationship records and Firestore rules that a future Parent
Portal milestone will read.

## Models

### Student (`lib/features/students/domain/student.dart`)

The permanent identity record: `studentId`, `schoolId`, `branchId`,
`admissionNumber`, `studentCode`, name parts (`firstName`/`middleName`/
`lastName`, plus a derived, stored `displayName`/`displayNameLower`),
`dateOfBirth`, `gender`, `bloodGroup` (nullable), `photoUrl`, contact/
address fields, `admissionDate`, `status` (+ `statusChangeReason`/
`statusChangeDate`/`statusChangeNotes`, see "Status lifecycle" below), and
a **current-placement cache**: `currentAcademicYearId`/`currentClassId`/
`currentSectionId`/`currentRollNumber`.

### Why a current-placement cache, not just academic history

The brief is explicit: "do NOT store the student's current class and
section as the only permanent source." The cache on `Student` exists
*alongside* the real history, not instead of it — it answers "which
class/section is this student in right now" in O(1) (one document read),
which every list screen needs, without scanning the `academicRecords`
subcollection on every row. The cache is never independently editable —
`Student.toFirestoreCurrentPlacementUpdate` is only ever called by
`StudentRepository.admitStudent`/`transferStudent`, in the same batch
that also writes the real `academicRecords` document, so the two can
never drift.

### Admission number vs. student code

- **Admission number** (`ADM-2026-001`-style): manually entered at
  admission, the official identifier used on physical documents/receipts.
  Validated for uniqueness within the branch (see "Duplicate prevention"
  below), but the *format* is not enforced — the brief explicitly asked
  not to build a numbering-rules engine this milestone; a school can type
  whatever convention it uses today.
- **Student code** (`STU-XXXXXXXX`): system-generated from the new
  student document's own Firestore-assigned id
  (`'STU-' + doc.id.substring(0, 8).toUpperCase()`) at admission time,
  never user-editable. A stable internal reference that never changes
  even if the school later changes its admission-number convention.
  Deliberately *not* a transactional auto-incrementing counter — that
  would need a dedicated counter document and contention handling for a
  problem uniqueness-via-doc-id already solves for free.

### StudentStatus

`ACTIVE | INACTIVE | TRANSFERRED | GRADUATED | LEFT`. Students are never
hard-deleted (brief §2) — every status change goes through
`StudentRepository.changeStudentStatus`, which also records
`statusChangeReason`/`statusChangeDate`/`statusChangeNotes` directly on
the student document (not a separate history subcollection — the brief
asked to "capture appropriate: effective date, reason, notes," not to
build a full audit-log entity for status changes specifically).

### StudentAcademicRecord (`academicRecords` subcollection)

The real source of truth for "where was this student, and when":
`recordId`, `studentId`, `schoolId`, `branchId`, `academicYearId`,
`classId`, `sectionId`, `rollNumber`, `startDate`, `endDate` (null while
active), `status` (`ACTIVE | COMPLETED | TRANSFERRED | WITHDRAWN`), full
audit fields. One document per placement. **Never edited to point at a
different placement** — `firestore.rules` enforces this by only allowing
`status`/`endDate`/`rollNumber` to change on update (see "Security
rules"). A placement change always means: close the current active
record, create a brand-new one.

The brief's suggested field list also included an `admissionDate` on this
entity; it was dropped as redundant with `startDate` (which already means
"when did this specific placement begin") — the *original* admission
date lives once, on `Student.admissionDate`. Two fields with overlapping
meaning is exactly the "admission number vs. student code" mistake the
brief itself warns against, applied to a different pair.

### Parent (`lib/features/students/domain/parent.dart`)

Contact record: `parentId`, `schoolId`, `branchId`, name parts, `phone`,
`alternatePhone`, `email`, `occupation`, `photoUrl`, address fields,
`status` (reuses the shared `ActivationStatus` enum from Milestone 2 —
no need for a parent-specific active/inactive type), and `linkedUserId`
(nullable — see "Parent portal access foundation").

**Deliberately has no `relationshipType` field.** The brief's suggested
field list put one there, but relationship type belongs on the
*relationship*, not the person — the same adult could in principle be
recorded as "guardian" for one child and "father" for another. Putting it
on `Parent` would have been the same "two identifiers, one purpose"
mistake the brief calls out for admission number vs. student code, just
applied one level up.

### ParentStudentLink (`parentLinks` subcollection, under the student)

The actual many-to-many bridge (brief §9): `relationshipId` (== the
parent's id — see below), `schoolId`, `branchId`, `studentId`, `parentId`,
`relationshipType`, `isPrimary`, `isEmergencyContact`, `canAccessPortal`,
`status`, full audit fields. Lives at
`students/{studentId}/parentLinks/{parentId}` — **the document id is the
parent id**, so "is this parent already linked to this student" is an
existence check, not a query, and a duplicate relationship is prevented
by construction rather than by an extra uniqueness check.

## Data relationships

```
School
  └─ Branch
       ├─ AcademicYear ─ Class ─ Section ─ Subject (Milestone 2)
       │
       ├─ Student
       │    ├─ academicRecords/{recordId}  ← history (source of truth)
       │    └─ parentLinks/{parentId}      ← this student's guardians
       │
       └─ Parent
            (no direct pointer to its children — see below)
```

`Student.currentAcademicYearId`/`currentClassId`/`currentSectionId` are a
*cache* of the latest `academicRecords` entry, not a foreign key
relationship in their own right.

### Querying both directions

- **"Who are this student's parents?"** — list
  `students/{id}/parentLinks`. Direct subcollection read, no index
  needed beyond the automatic one.
- **"Which students belong to this parent?"** (brief §22, and needed by
  the eventual Parent Portal) — a Firestore **collection-group** query:
  `collectionGroup('parentLinks').where('schoolId', '==', ...)
  .where('parentId', '==', ...)`, then one `get()` per matching link to
  fetch the actual `Student` document (`ParentRepository.getChildrenForParent`).
  This needed one explicit entry in `firestore.indexes.json` (collection-
  group queries are not auto-indexed the way single-collection queries
  are). The alternative — denormalizing a list of student ids onto
  `Parent` — was rejected: it would need to be kept in sync on every
  link/unlink, for a query that already has a correct, if slightly more
  expensive, answer without denormalization.

## Status lifecycle

```
ACTIVE ──change status──> INACTIVE / TRANSFERRED / GRADUATED / LEFT
```

No hard deletes, ever (brief §2, §20). `StudentRepository.changeStudentStatus`
is the only path that changes `Student.status`; it is a plain document
update (not a batch), since a status change does not need to touch
`academicRecords` — a withdrawn student's placement history should stay
exactly as it was, untouched.

## Transfer / academic history rule

```
Student: Arun
  2026-27  Class 5  Section A   (academicRecords/rec-1: status COMPLETED, endDate set)
  2027-28  Class 6  Section B   (academicRecords/rec-2: status ACTIVE,   endDate null)
```

`StudentRepository.transferStudent` does this in **one atomic batch**:

1. Find the current `ACTIVE` `academicRecords` document(s) and close each
   one (`status` → `TRANSFERRED` or `COMPLETED`, `endDate` → now).
2. Create a brand-new `academicRecords` document for the new placement
   (`status` → `ACTIVE`, `startDate` → now).
3. Update `Student`'s current-placement cache to the new values.

All three or none — a half-applied transfer (new record created, old one
left dangling as still-ACTIVE, or the cache pointing somewhere the
history doesn't agree with) is exactly the "partially-created
relationship" failure mode the brief warns against in §33.

**Branch transfer was out of scope in this milestone — it now exists as a separate, audited action (see `docs/multi-branch.md` §3).** A student document lives
under one specific `branches/{branchId}` path; moving it to a different
branch means creating a new document under a different path and
migrating every subcollection underneath it — a genuinely different, more
complex operation than a same-branch placement change. Per the brief's
own permission to do this ("if ... not fully supported yet, do not fake
it. Document the limitation."), `StudentTransferDialog` only offers
year/class/section changes within the student's current branch.

## Admission flow

```
Add Student
  ↓
Basic Information (name, DOB, gender, blood group, admission #, contact/address)
  ↓
Parent / Guardian (optional at this stage — link existing, add new, or skip)
  ↓
Academic Placement (academic year → class → section, roll number)
  ↓
Review → Save
```

Condensed from the brief's 7-step diagram into 4 pages/steps: "Class" and
"Section" are one step (a cascading pair of dropdowns is one cohesive UI
unit, not two separate decisions in practice), and "Review"/"Save" are
the same step. The Parent step is **optional and skippable** — a parent
may not be available at admission time in practice, and a student must
never be blocked on it; `admitStudent` succeeds without any parent link,
and one can be added later from the Student Profile page's "Add parent"
action (`LinkParentDialog`, the same widget the wizard's Parent step
embeds inline).

`admitStudent` validates, in order: admission-number uniqueness within
the branch (a live Firestore query, not just a UI check), and that the
chosen section genuinely belongs to the chosen class/year/branch (a
`get()` on the exact nested path — if it resolves, the hierarchy is
correct by construction, since the path itself encodes
year→class→section). Only then does it batch-write the student and its
first academic record.

## Parent portal access foundation

Brief §10: "establish the correct relationship and authorization
foundation" for a future Parent Portal, without building the portal
itself. This milestone's half of that foundation:

- `Parent.linkedUserId` — set once an admin links this contact record to
  an existing `/users/{uid}` account with `role == PARENT`.
- `UserProfile.linkedParentId` — the reverse pointer, read by
  `firestore.rules`' `canAccessAsParent()` so a rule evaluation can go
  from "this is the caller's uid" to "this is their Parent record" in one
  `get()`, without a query (rules can't run arbitrary queries).
- `ParentRepository.linkPortalAccess` writes both sides in one batch.

What is *not* built: a UI to create the underlying Firebase Auth account
for a parent (the same gap Milestone 1 already documented for staff —
"No way to create a Firebase Auth account for another person" — applies
identically here), and the Parent Portal's actual screens. Those are
future-milestone work; this milestone only had to make the relationship
*correctly enforceable*, which the rules tests prove it is.

## Permissions

| Role | Manage (create/edit/transfer/withdraw) | View | Notes |
|---|---|---|---|
| Platform Admin | ✅ | ✅ | `manageStudentData` + `viewStudentData` |
| School Admin | ✅ (any branch) | ✅ | |
| Branch Admin | ✅ (own branch only) | ✅ (own branch) | |
| Teacher | ❌ | ✅ (own branch) | Brief §35: "read students assigned to their classes" — the class-scoping hook doesn't exist yet (needs a teacher-class assignment model, Milestone 4 territory); for now, teachers get branch-wide read, same breadth as `viewAcademicSetup`. |
| Finance | ❌ | ✅ (own branch) | For future fee management (brief §35). |
| Parent | ❌ | Relationship-based only | **Not** `viewStudentData` — see below. |

`Permission.manageStudentData`/`viewStudentData` (new this milestone)
cover students, parents, academic records, and parent links together —
one pair, not four, since they are one tightly-coupled master-data
module and the brief does not ask for independently configurable access
between "manage students" and "manage parents."

## Security rules

### Tenant + role authorization (the manage/view split)

`canManageStudentData(schoolId, branchId)` / `canViewStudentData(schoolId,
branchId)` mirror `canManageAcademicSetup`/`canViewAcademicSetup` from
Milestone 2 exactly — same admin-hierarchy logic, same TEACHER/FINANCE
read grant, same absence of PARENT from either function.

### Parent isolation (the relationship-based path)

```
function canAccessAsParent(schoolId, branchId, studentId) {
  let linkedParentId = callerProfile().linkedParentId;
  let linkPath = parentLinkPath(schoolId, branchId, studentId, linkedParentId);
  return isActiveCaller()
    && callerRole() == 'PARENT'
    && callerSchoolId() == schoolId
    && linkedParentId != null
    && exists(linkPath)
    && get(linkPath).data.canAccessPortal == true
    && get(linkPath).data.status == 'ACTIVE';
}
```

A `PARENT` gets no standing permission at all — every read of a student
(or that student's `academicRecords`) is this specific check, re-run
against this specific `studentId`. Reading `/parentLinks/{parentId}`
directly (e.g. to see one's own relationship flags) uses a simpler,
equivalent check: `callerProfile().linkedParentId == parentId`, since the
wildcard in that path already *is* the parent id being tested, with no
extra `get()` needed.

### Immutable/protected fields

- `schoolId`/`branchId`/`studentId`/`parentId` on every nested document:
  checked against `request.resource.data.X == <path segment>` on create,
  and simply absent from every `changedOnly([...])` list on update — an
  update that tries to change them is rejected by the field-scoping
  check alone, the same pattern used everywhere else in this app.
- `createdAt`/`createdBy`: enforced immutable by `validUpdateAudit()`,
  shared with every other collection.
- `academicRecords`: `changedOnly(['status', 'endDate', 'rollNumber', ...])`
  — `classId`/`sectionId`/`academicYearId` cannot be changed on an
  existing record by any caller, rules included. This is what makes
  "never overwrite history" a server-enforced guarantee, not just an
  app-level convention `FirebaseStudentRepository` happens to follow.

### A necessary extension to the existing `/users/{userId}` rule

Granting parent portal access writes `linkedParentId` on `/users/{uid}`.
The *existing* (Milestone 1) school-admin/branch-admin update branches
of that rule did not include `linkedParentId` in their `changedOnly([...])`
lists — before this milestone, only a `PLATFORM_ADMIN` could have written
it. Extended both branches to include `linkedParentId` (and nothing
else), so a school/branch admin can grant portal access the same way they
already manage every other field on a subordinate's profile.

### Storage rules

`storage.rules` gained two more path patterns, mirroring the school-logo
rule's shape exactly: `schools/{schoolId}/branches/{branchId}/students/
{studentId}/{fileName}` and the equivalent for `parents`. Read: same
school+branch, or a manage-level admin. Write: manage-level admin only,
2MB size cap, `image/*` content-type check.

## Queries and indexes

Every Student/Parent list is **cursor-paginated**
(`firestore-tests` proves the rules; `PagedResult<T>` + `.limit(pageSize
+ 1)` + `startAfterDocument` proves the pagination shape in the
repository) — never an unbounded `.get()` of the whole collection, per
brief §31.

`firestore.indexes.json` (new this milestone) declares:

- `students`: `(status, displayNameLower)` — the default roster view,
  filtered by status, sorted/paginated by name.
- `students`: `(currentAcademicYearId, currentClassId, displayNameLower)`
  and `(currentAcademicYearId, currentClassId, currentSectionId,
  displayNameLower)` — "students currently in this class/section."
- `parents`: `(status, displayNameLower)` — same shape as `students`.
- `parentLinks` (**collection group**): `(schoolId, parentId)` — the
  "which students belong to this parent" query.

Name search (`searchStudentsByName`/`searchParentsByName`) and
admission-number search (`searchStudentsByAdmissionNumber`) use the
standard Firestore prefix-range idiom (`orderBy` + `startAt`/`endAt` on a
lowercased field) — no composite index needed beyond the automatic
single-field index, since the query orders by the same field it ranges
on. Combining a free-text search with a class/section/status filter at
the same time is deliberately not supported server-side (it would need a
combinatorially larger set of composite indexes for a rarely-used
combination); the UI treats search and the placement/status filters as
alternatives, not simultaneous dimensions.

## Duplicate prevention

- **Admission number**: a live Firestore query inside
  `admitStudent`/`updateStudentProfile` (`isAdmissionNumberAvailable`),
  same "data-quality check, not tenant isolation" reasoning as Milestone
  2's duplicate-class-name check — enforced in the repository, not rules.
- **Parent-student relationship**: prevented by construction (document id
  == parent id, see `ParentStudentLink`'s doc comment) — there is no way
  to create a second link document for the same parent+student pair.
- **Academic enrollment**: a student has at most one `ACTIVE`
  `academicRecords` document at a time by construction —
  `transferStudent` always closes every currently-`ACTIVE` record in the
  same batch it opens the new one.

## Known issues (Milestone 3)

- **No Dart-level repository tests** for admission-number uniqueness or
  the section/class/year referential check — covered by Firestore rules
  tests (tenant/role authorization) and model-serialization tests, not a
  live-Firestore integration test. Same gap, same reasoning, as
  Milestone 2's academic-structure repository.
- **Teacher read access is branch-wide, not class-scoped.** Brief §35
  anticipates narrowing this once a teacher-class assignment model
  exists (Milestone 4 territory) — tracked as the specific next step for
  `canViewStudentData`.
- **No self-service parent portal-access flow** — see "Parent portal
  access foundation" above.
- **No pagination UI polish** (no page-number indicator, no "jump to
  page") — "Load more" only. Acceptable at the scale this app targets;
  flagged since the brief was explicit about designing lists "for
  growth."
- **Branch transfer** is handled by `docs/multi-branch.md` §3 (it was not supported here) — see "Transfer / academic history
  rule" above; documented, not faked.
