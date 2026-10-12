# Milestone 4 — Staff + Teacher Management

Companion to `PROJECT_ARCHITECTURE.md` (where things live),
`FIRESTORE_ARCHITECTURE.md` (collection design), and
`SECURITY_ARCHITECTURE.md` (rules and roles). This is the full reference
for the staff/teacher module: models, relationships, permissions, security
rules, queries and indexes, and what was deliberately left out.

## What this milestone builds

- **Staff master records** — one person record for everyone who works at the
  school (teachers, accountants, principal, drivers, librarians, ...).
- **Departments** and **designations** — per-branch configuration lists.
- **Employment lifecycle** — `ACTIVE`, `INACTIVE`, `ON_NOTICE`, `RESIGNED`,
  `TERMINATED`, `RETIRED`; never a delete.
- **Teacher assignments** — academic-year-aware, historical: which teacher
  teaches which subject to which section in which year, and who is a
  section's class teacher.
- **Staff photo** and a **documents foundation** (Storage-backed metadata).
- Staff list, teacher list, staff profile (which doubles as the teacher
  profile), `/my-profile` for a signed-in teacher, department and
  designation screens.

Not built (by design, see "Out of scope"): attendance, leave, payroll,
homework, timetable, exams, notifications.

## The core modelling decision: teacher is a capability, not a second person

```
School ─ Branch ─ Staff ─┬─ Department   (departmentId → departments)
                         ├─ Designation  (designationId → designations)
                         ├─ User account (userId → /users/{uid}, optional)
                         └─ isTeacher? ──► TeacherAssignment (many)
                                             ├─ Academic Year
                                             ├─ Class
                                             ├─ Section
                                             └─ Subject  (or: class teacher)
```

There is **no teacher collection**. A staff member with `isTeacher = true`
has teaching responsibility; *what* they teach lives in
`teacherAssignments`. Nothing about the person is duplicated, and the
teacher profile is the staff profile plus a **Teaching** tab.

### Four identifiers, never conflated

| Name | What it is | Where |
|---|---|---|
| `staffId` | Firestore document id; opaque, permanent; what other collections reference | `staff/{staffId}` |
| `employeeCode` | Human-facing code (`EMP-0001`), typed by an admin, unique per branch, correctable | `staff.employeeCode` |
| `userId` | Optional link to the application account (== Firebase Auth uid) | `staff.userId` |
| Firebase Auth uid | The sign-in identity | `/users/{uid}` only |

A staff member can exist with no login (`userId == null`) — nothing creates
a Firebase Auth account automatically. Email is **never** the identity key;
it is only contact data (and a search field).

### Designation is not a role

`designationId` ("Senior Teacher") is descriptive. What a person may *do*
comes from the linked `/users` account's role and the existing
`RolePermissions` map. No rule or permission reads the designation. This is
covered by a rules test ("a staff record titled Principal gives no access").

## Collections

All under `/schools/{schoolId}/branches/{branchId}/`:

| Path | Purpose | Doc id |
|---|---|---|
| `staff/{staffId}` | The staff master record | auto |
| `staffCodes/{codeLower}` | Employee-code reservation (uniqueness) | lower-cased code |
| `staff/{staffId}/documents/{documentId}` | Document metadata | auto |
| `departments/{departmentId}` | Department config | lower-cased code |
| `designations/{designationId}` | Designation config | lower-cased code |
| `teacherAssignments/{assignmentId}` | One teaching assignment (history kept) | auto |
| `assignmentSlots/{slotKey}` | Active-assignment uniqueness reservation | `year__class__section__subjectId` or `...__CLASS_TEACHER` |

Staff are branch-scoped (like students), so branch isolation is structural
as well as rule-enforced. Assignments sit flat under the branch — not under
`academicYears/…` — so "everything this teacher ever taught" is one query
across years.

### Staff fields

`employeeCode`, `employeeCodeLower`, `firstName`, `middleName`, `lastName`,
`displayName`, `displayNameLower`, `photoUrl`, `dateOfBirth`, `gender`,
`bloodGroup`, `phone`, `alternatePhone`, `email`, `emailLower`, `address`,
`city`, `state`, `country`, `postalCode`, `joiningDate`, `employmentType`,
`departmentId`, `designationId`, `status`, `isTeacher`, `userId`,
`statusChangeReason/Date/Notes`, plus `schoolId`, `branchId` and the audit
fields (`createdAt/By`, `updatedAt/By`). `staffId` is the document id, not
a stored field. The `*Lower` fields are derived search keys.

`EmploymentType`: `FULL_TIME`, `PART_TIME`, `CONTRACT`, `TEMPORARY`,
`INTERN`, `OTHER` — informational only; no payroll rule keys off it.

### Employee code uniqueness (per branch)

A code is reserved by writing `staffCodes/{codeLower}` **in the same batch**
as the staff document. The rules require:

- on staff create: the reservation exists after the batch and names this
  staff id (`existsAfter`/`getAfter`);
- on reservation create: the doc id must equal the staff record's
  `employeeCodeLower`; a second create on an existing id is an *update*,
  which is denied — so a duplicate is impossible even under a race;
- on reservation delete: only if no staff record holds that code any more
  (the code-change batch deletes the old reservation and creates the new
  one atomically).

Codes are case-insensitive (`emp-0001` collides with `EMP-0001`) and must
match `^[A-Za-z0-9_-]{2,20}$`. Scope is the **branch**; making it
school-wide later means moving the reservations to
`/schools/{s}/staffCodes` and widening one rule. Auto-numbering is not
built — the reservation design leaves room for a numbering service to
claim codes the same way.

### Departments and designations

Same shape: `name`, `code`, `description`, `status`, tenant ids, audit
fields. The **document id is the lower-cased code**, which makes duplicate
codes impossible (Firestore refuses the second create) and the code
immutable (it is the id). Name, description and status stay editable. They
are deactivated, never deleted; an inactive entry cannot be chosen for new
or moved staff but stays resolvable on existing records.

## Staff lifecycle

```
ACTIVE ──► ON_NOTICE ──► RESIGNED | TERMINATED          (final)
  │  ▲        └────────► ACTIVE | INACTIVE
  │  └── INACTIVE
  └────────► RESIGNED | TERMINATED | RETIRED             (final)
```

- Encoded in `StaffStatus.allowedTransitions`, enforced by
  `StaffRepository.changeStaffStatus`. `firestore.rules` independently
  blocks leaving `RESIGNED`/`TERMINATED`/`RETIRED`.
- A record is **never deleted**: the rules have `allow delete: if false`
  everywhere in this module. Attendance, leave, payroll and audit can rely
  on the id and the employee code reservation remaining.
- Moving to `INACTIVE`/`RESIGNED`/`TERMINATED`/`RETIRED` **ends the
  teacher's active assignments** (status `ENDED`, end date = effective date)
  and frees their slots in the same batch. The assignment rows stay. `ON_NOTICE`
  keeps assignments (they are still working) but allows no new ones.
- Reactivating an `INACTIVE` member does not resurrect old assignments.
- Only `ACTIVE` teachers can receive new assignments — checked by the
  repository (clear message) and by the rules (`get(staff).status == 'ACTIVE'`
  and `isTeacher == true`).

## Teacher assignments

### Model

`teacherAssignments/{id}`: `academicYearId`, `teacherStaffId`, `classId`,
`sectionId`, `subjectId` (null for class teacher), `isClassTeacher`,
`startDate`, `endDate`, `status` (`ACTIVE`/`ENDED`), tenant ids, audit
fields. Ids only — never names — so renaming a class does not rewrite
history.

Changing what someone teaches **ends** the old row and **creates** a new
one; nothing is overwritten. So for Arun:

```
2026-27   Class 5-A Mathematics   ENDED  (kept)
2026-27   Class 6-B Mathematics   ENDED  (kept)
2027-28   Class 6-A Mathematics   ACTIVE
2027-28   Class 7-B Mathematics   ACTIVE
```

The Teaching tab groups rows by academic year, active and ended together.

### Uniqueness: the slot

Rules cannot query, so "one class teacher per section" cannot be a rule
that scans assignments. Each active assignment instead claims a **slot**
document whose id is its identity:

```
subject assignment:  {yearId}__{classId}__{sectionId}__{subjectId}
class teacher:       {yearId}__{classId}__{sectionId}__CLASS_TEACHER
```

The assignment and its slot are created in one batch; the rules require
both (the slot's id must match the assignment's fields, its `assignmentId`
must point back). A second claim is an update on an existing id and is
denied. Ending an assignment deletes the slot in the same batch (the rules
require the slot be gone after the batch, and only allow its deletion when
the assignment is `ENDED`).

Consequences, documented rather than hidden:

- **At most one active class teacher per section per year.** Co-class-
  teachers are not supported.
- **At most one active teacher per section + subject + year.** A subject
  co-taught by two teachers in one section is not supported. (Relaxing
  either rule means changing the slot key, e.g. appending the teacher id.)
- **A teacher may be class teacher of several sections**, and may be both
  class teacher *and* a subject teacher in the same section (different
  slots).
- To **replace** a class teacher, end the current assignment first, then
  assign the new one. It is two steps on purpose: a replace-in-one-batch
  would delete and re-create the same slot document in one write, which the
  rules cannot reason about safely.

### Validation (client message + server enforcement)

| Check | Client (`TeacherAssignmentRules`) | `firestore.rules` |
|---|---|---|
| Staff exists, same tenant | looked up under the branch | `get(staffPath(school, branch, id))` |
| Staff active | yes | `status == 'ACTIVE'` |
| Staff has teaching responsibility | yes | `isTeacher == true` |
| Academic year exists / not closed | yes | via the section path (below) |
| Section exists under class + year, active | yes | `get(sectionPath(...)).status == 'ACTIVE'` |
| Subject configured for the class | yes | `exists(classSubjectPath(...))` |
| No duplicate / second class teacher | slot lookup | slot create + `existsAfter` |
| Tenant / branch | n/a | `canManageStaff(schoolId, branchId)` |

The client never needs to be trusted: every reference above is re-verified
in the rules, so a hand-crafted request with a School B id, a stale subject,
an inactive section or a non-teacher is refused. (A *closed* academic year
is refused with a friendly message by the client only; the rules treat
year state as outside their job.)

`TeacherAssignmentRules` holds these checks as pure functions so they are
unit-tested without Firestore; `FirebaseTeacherAssignmentRepository` just
fetches the documents and calls them.

## Permissions

New in `core/permissions/permission.dart` (still one RBAC system — no
second permission mechanism):

| Permission | Granted to |
|---|---|
| `manageStaff` | platform admin, school admin, branch admin |
| `viewStaff` | the above + finance (own branch) |
| `viewOwnStaffProfile` | platform admin, teacher, finance (drives `/my-profile`) |

| Role | Staff directory | Own profile + assignments | Write |
|---|---|---|---|
| Platform / School admin | all branches of the school | — | yes |
| Branch admin | own branch only | — | own branch |
| Teacher | **no** | `/my-profile`, own assignments | no |
| Finance | read, own branch | `/my-profile` | no |
| Parent | none | none | none |

Routes are guarded through `AppRoutes.requiredPermissions` (the single
map the router and the navigation both read). Navigation: **Staff**
(`viewStaff`) with a Staff | Teachers switcher inside it, and **My Profile**
(`viewOwnStaffProfile`). Teachers and the staff directory share one nav
destination to keep the mobile bottom bar usable.

## Security rules (summary)

Helpers in `firestore.rules`: `canManageStaff`, `canViewStaff`,
`isOwnStaffRecord`, `slotKeyOf`, `isTerminalStaffStatus`, path builders.

- **Tenant isolation.** Every rule starts from the path's `schoolId`/
  `branchId` and compares against the caller's `/users` profile. School B
  cannot read or write School A staff, departments, designations,
  assignments, slots or documents. Tested.
- **Branch isolation.** Branch admins manage only their branch; the same
  functions gate every sub-collection. Tested (North ↔ South).
- **Teacher.** Reads *only* the staff record whose `userId` is theirs, and
  only assignments whose `teacherStaffId` resolves (via that staff record's
  `userId`) to them. No colleague's staff record, no `staffCodes`, no
  documents, no write. Departments/designations are readable (to render
  their own profile).
- **Finance.** Reads staff in own branch; no write, no documents.
- **Parent.** Nothing.
- **Immutable.** `schoolId`, `branchId`, `createdAt`, `createdBy` cannot
  change (they are absent from every `changedOnly` list, and
  `validUpdateAudit` pins the creation audit). Audit actors must equal the
  caller; timestamps must be `request.time`.
- **Status finality**, **active-reference** checks (department/designation
  must be `ACTIVE` when set or changed), **linked user must be in the same
  school**, **new staff start `ACTIVE` and unlinked**.
- **No hard delete** anywhere in the module.

Tests: `firestore-tests/staff-rules.test.mjs` (28) and
`firestore-tests/staff-storage-rules.test.mjs` (4). The suite was
mutation-checked: temporarily removing the `isTeacher` check, the
class-subject check, the read scoping and the terminal-status check each
made tests fail.

### Storage

`storage.rules` additions:

- `staff/{staffId}/photo` — fixed object name `photo` (replace overwrites),
  images only, < 2 MB, readable by the same branch, writable/deletable by
  managers. Delete exists for "Remove photo".
- `staff/{staffId}/documents/{documentId}/{fileName}` — managers only for
  **read and write** (ID proofs and certificates are sensitive: not even
  same-branch teachers or finance), PDF/JPEG/PNG, < 5 MB, never deletable.

## Documents foundation

Upload (type, title, file) → Storage object + `documents/{id}` metadata
(`storagePath`, not a URL; no bytes in Firestore). Listing, open (download
URL fetched on demand), and **soft** remove (`status = REMOVED`; Storage
forbids delete). If the metadata write fails after upload the file is
deleted best-effort. No approval flow, expiry tracking or versioning.

## Queries and indexes

Staff list:

- Browse: equality filters on `status`, `departmentId`, `designationId`,
  `employmentType`, `isTeacher` (any combination) + `orderBy
  displayNameLower`, cursor-paginated (`limit(pageSize + 1)` +
  `startAfterDocument`). Firestore serves a multi-filter query by merging
  composite indexes, so one `(field, displayNameLower)` index per filter
  field is enough — five on `staff`, rather than the combinatorial set.
- Search: prefix range on one field at a time — `displayNameLower`,
  `employeeCodeLower`, `phone`, `emailLower` — each a single-field index
  (automatic). Search and the browse filters are **mutually exclusive** in
  the UI (a message says so); combining them would need an index per
  combination. The one exception is the teacher list's name search, served
  by `(isTeacher, displayNameLower)`.

Teacher list:

- Without a class/section/subject filter: `staff` where `isTeacher == true`
  (+ status or name search), paginated, then **one** assignments query per
  30 teachers (`whereIn teacherStaffId` + `academicYearId ==`) to fill
  subjects/classes — not one per teacher.
- With a filter: page through the year's ACTIVE assignments matching
  class/section/subject (equality only; no composite index), resolve the
  teachers with a `documentId whereIn` (30 at a time), dedupe across pages.
  Search and status are paused in that mode.

Other: assignment history `teacherAssignments` `teacherStaffId ==` +
`orderBy startDate desc` (composite index); section view and per-section
queries are equality-only.

`firestore.indexes.json` additions: `staff` × 5 (`status`, `isTeacher`,
`departmentId`, `designationId`, `employmentType`, each with
`displayNameLower`) and `teacherAssignments` (`teacherStaffId`,
`startDate` desc). `staffCodes`, `departments`, `designations`,
`assignmentSlots` and documents need none.

## Code layout

```
lib/features/staff/
  domain/        Staff, StaffStatus, EmploymentType, Department, Designation,
                 TeacherAssignment (+status), StaffDocument, StaffSearchField,
                 TeacherAssignmentRules; StaffRepository, StaffSetupRepository,
                 TeacherAssignmentRepository interfaces
  data/          FirebaseStaffRepository, FirebaseStaffSetupRepository,
                 FirebaseTeacherAssignmentRepository
  presentation/
    pages/       StaffListPage, StaffFormPage, StaffProfilePage (+StaffProfileView),
                 MyStaffProfilePage, TeachersListPage, StaffConfigPage
    widgets/     StaffBranchScope, StaffSectionSwitcher, StaffStatusDialog,
                 LinkUserDialog, TeacherAssignmentDialog, TeachingTab,
                 StaffDocumentsTab, StaffConfigFormDialog, FormGrid, ...
    providers/   staff_providers.dart (repositories, streams, write
                 controllers), academic_names_provider.dart, staff_keys.dart
    staff_routes.dart
lib/shared/paging/paged_list_controller.dart   reusable cursor pager
```

Reused rather than rebuilt: tenant context, `RolePermissions`, router guard
map, `ResponsiveDataList`, `showAdaptiveAppDialog`, `PersonPhotoPicker`
(gained an optional `onRemove`), `PagedResult`, `Gender`, `BloodGroup`,
`ActivationStatus`, the Milestone 2 providers for years/classes/sections/
subjects/class-subjects.

New dependencies: `file_picker` and `url_launcher` (documents need PDF
selection and opening). Nothing else.

## Testing

| Layer | What | Count |
|---|---|---|
| Unit | Staff / status / department / designation / assignment / slot / document models, `TeacherAssignmentRules`, permissions | `test/staff/*`, `test/core/role_permissions_test.dart` |
| Widget | route + nav permissions per role, staff list (desktop/tablet/mobile, empty, error, search, filters), profile, status dialog, create form validation + overflow, assignment dialog | `test/widget/staff_ui_test.dart`, `teacher_assignment_dialog_test.dart` |
| Rules (emulator) | tenant/branch/role isolation, code uniqueness, immutables, lifecycle, references, slots, history, documents, Storage | `firestore-tests/staff-*.test.mjs` |

## Known issues

See the final report for the classified list (P0–P3). The structural ones:

- Repository classes are not exercised against Firestore by automated tests
  (no Dart Firestore fake compiles on the pinned Flutter SDK); persistence
  rules are, via the emulator.
- `isTeacher` cannot be turned off while active assignments exist, but only
  the client checks it (rules cannot query).
- A user ID can be linked to one staff member per branch by the client; the
  rules do not enforce one-to-one across the school.
- Teachers keep the branch-wide student read granted in Milestone 3; this
  milestone does not narrow it to "their own sections" (the assignment data
  now exists to do so).
- No UI lists `/users`, so linking an account needs the user's ID.

## Out of scope

Staff attendance, student attendance, payroll/salary/payslips, leave,
homework, timetable, exams/marks/report cards, advanced notifications, HR
performance management. The model supports them: `staffId` is a stable,
never-deleted reference; employment type, joining date and status history
fields exist; assignments give timetable and homework a ready
teacher-to-section relationship.
