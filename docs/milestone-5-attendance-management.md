# Milestone 5 — Attendance Management

Companion to `PROJECT_ARCHITECTURE.md`, `FIRESTORE_ARCHITECTURE.md` and
`SECURITY_ARCHITECTURE.md`. The full reference for student and staff
attendance: models, workflows, finalization and corrections, calendar
integration, percentage definition, queries/indexes, permissions, rules,
tests and known limitations.

## What this milestone builds

- **Student attendance** by class and section, for any date, with bulk
  marking, partial-save confirmation, finalization, corrections with a
  reason, per-change history, and a conflict check against concurrent edits.
- **Staff attendance** per branch and date, same engine.
- **Holiday / working-day integration** using the Milestone 2 calendar.
- **Dashboard** (`/attendance`), **daily/monthly reports** with attendance
  percentage, per-person drill-down, and CSV copy.
- Role-based access on the existing RBAC, enforced in `firestore.rules`.

Not built: Leave, Fees, Homework, Payroll, Parent Portal views,
notifications, offline sync, shift/overtime.

## Gaps found in earlier milestones, and the smallest extensions made

| Gap | Extension |
|---|---|
| The calendar had no "special working day" (a Saturday that is a school day). | `HolidayType.specialWorkingDay` (`SPECIAL_WORKING_DAY`) — one new enum value. It appears in the existing holiday form automatically as "Special working day". No holiday rules changed. |
| No query for "students enrolled in this section on this date". | Collection-group query over `academicRecords` (equality on school, branch, year, class, section) + a date filter in Dart; one collection-group `read` rule and one index. |
| A teacher had no link to "their" sections for marking. | Reused Milestone 4's class-teacher assignment slot — nothing new stored. |
| `Student` had no roll-number label. | `Student.rollNumberLabel` getter. |
| No conflict error type. | `ConflictFailure` in `app_failure.dart`. |
| `AcademicSettings.attendanceCutoffTime` exists but nothing uses it. | Left unused; documented under limitations. |

## Data model

All under `/schools/{schoolId}/branches/{branchId}/` (branch-scoped, like
students and staff):

| Path | Purpose | Doc id |
|---|---|---|
| `studentAttendance/{id}` | One student, one date | `{dateKey}_{studentId}` |
| `studentAttendance/{id}/history/{n}` | Immutable audit entry per revision | revision number |
| `attendanceSessions/{id}` | One section's register for a date: DRAFT/FINALIZED + counts | `{dateKey}__{yearId}__{classId}__{sectionId}` |
| `staffAttendance/{id}` | One staff member, one date | `{dateKey}_{staffId}` |
| `staffAttendance/{id}/history/{n}` | Audit entry per revision | revision number |
| `staffAttendanceDays/{dateKey}` | The branch's staff register for a date | `{dateKey}` |

(Names follow the project's camelCase collection convention rather than the
suggested `student_attendance`.)

### Student attendance fields

`schoolId`, `branchId`, `academicYearId`, `dateKey`, `attendanceDate`,
`studentId`, `academicRecordId`, `classId`, `sectionId`, `status`,
`remarks`, `revision`, `lastChangeReason`, `createdAt/By`, `updatedAt/By`.
`checkInTime`/`checkOutTime` were optional in the brief and are omitted —
nothing needs them yet and they can be added without migration.

- **Dates.** `dateKey` is a `yyyy-MM-dd` string: a *civil date*, so there is
  no timezone arithmetic anywhere. Queries, ids and ranges use it (string
  order is chronological order). `attendanceDate` is the same date as a UTC-
  midnight `Timestamp` (the form `Holiday` already uses), for interop and
  the "not in the future" rule. "Today" is the device's date; the school's
  `timezone` setting is not consulted (see limitations).
- **Placement snapshot.** `academicYearId`, `classId`, `sectionId` and
  `academicRecordId` record where the student was *when it was marked*. They
  are immutable (rules), so a later transfer never rewrites history.
- **Statuses.** `PRESENT`, `ABSENT`, `LATE`, `HALF_DAY` for both students and
  staff. **Leave is deliberately not a status**: a future Leave module should
  reference attendance days instead of writing a contradictory `LEAVE`
  record. A rules test asserts `LEAVE` is rejected.

### Staff attendance fields

`schoolId`, `branchId`, `dateKey`, `attendanceDate`, `staffId`, `status`,
`remarks`, `revision`, `lastChangeReason`, audit fields. No shift, overtime
or pay fields.

### Register ("day") documents

`status` (`DRAFT`/`FINALIZED`), `enrolled`, `present`, `absent`, `late`,
`halfDay`, `notMarked`, `dayKind` (working / special working / non-working /
holiday), `overrideReason`, `revision`, `finalizedAt/By`, audit fields (and
year/class/section for student sessions). They give the dashboard one small
document per section instead of every student.

## Duplicate prevention, retries and concurrent edits

Three independent layers, none of them UI-only:

1. **Deterministic ids.** A student has exactly one possible document per
   date per branch (`{dateKey}_{studentId}`). A double-click, a retry, a
   re-opened screen or two users all target the same document. The rules
   require the id to equal `dateKey + '_' + studentId`, and a second
   "create" is an *update*, which the rules only allow with `revision + 1`.
2. **Revision check in a transaction.** `AttendanceRegisterTransaction`
   re-reads the register day and every entry inside one Firestore
   transaction and compares each stored `revision` with the one the user
   loaded. Any difference — someone else saved, the record vanished, or the
   student is already recorded in *another* section that day — throws
   `ConflictFailure` and **writes nothing**. A retry of a save that already
   succeeded therefore conflicts instead of duplicating. The comparison is
   the pure `AttendanceSavePlanner` (unit-tested).
3. **Rules.** `revision` must increase by exactly 1 on update and start at 1
   on create, so even a client that skips the transaction cannot silently
   write over a newer value.

The UI additionally disables every action while a save is in flight and
shows success only after the transaction completes.

A class save of N students costs N + 1 reads. It writes only the *changed*
records (2 writes each: record + history) plus 1 for the day document — so a
first save of 40 students is 81 writes and a correction of one student is 3.

## Student workflow

1. Branch (if the role is not branch-scoped) → **academic year → class →
   section → date**. A class teacher with a single section is taken straight
   to it.
2. The register loads the students enrolled **on that date** and their
   stored attendance. Enrollment comes from each student's `academicRecords`
   history, not the "current placement" cache, so a past date shows the class
   the student was really in:
   - a placement covers `[startDate, endDate)` as civil dates — the transfer
     day belongs to the *new* section only, so a student is never on two
     registers;
   - a student who later withdrew/graduated stays on the register for days
     before the status-change date (withdrawal does not close the record);
   - a student with a stored record who is no longer eligible is appended so
     stored attendance is never hidden.
3. Mark P / A / L / H per student, optional remarks. **Mark all present**
   fills only the *unmarked* — it never overwrites a status already chosen or
   saved. **Reset** returns one student to what is stored.
4. A summary shows Total · Present · Absent · Late · Half day · Not marked.
5. **Save.** If anyone is unmarked the user must confirm *partial*
   attendance; unmarked students stay "not marked" — never silently present
   or absent. **Finalize** needs everyone marked and a confirmation.

## Staff workflow

Branch → date → mark → save/finalize, managers only (`manageAttendance`);
finance sees the register read-only. Who appears is `StaffEligibility`:
joined on/before the date and either ACTIVE/ON_NOTICE or left only after the
date (their last status-change date is later). INACTIVE/RESIGNED/TERMINATED/
RETIRED staff leave the register from their status-change date, and **nobody
is marked automatically**. A reinstated staff member's earlier gap is not
tracked (only the latest status change is stored).

## Finalization and corrections

- A register is **DRAFT** while being entered and **FINALIZED** when locked.
- Once finalized, the rules allow student-record writes only to a manager
  (school/branch/platform admin), and only with a non-empty
  `lastChangeReason`. A teacher is refused by the rules — hiding the button is
  only a convenience. The same holds for adding a student to a finalized
  register and for staff days.
- Every change writes a `history/{revision}` entry in the same transaction:
  previous status, new status, remarks, reason, who, when (server time).
  History is immutable (`update`/`delete` denied) and its actor/time are
  rule-checked.
- The register document's revision also advances on every save.
- There is **no re-open UI**. The rules do let a manager set a finalized
  register back to DRAFT; the app does not offer it yet, since corrections
  work on a finalized register directly.
- There is no approval workflow.

## Holiday and working-day integration

`AttendanceCalendar.evaluate` uses the branch's `WorkingDays` and the
academic year's calendar entries (Milestone 2 providers — nothing is copied
into attendance). Precedence: active holiday (public/school/local/special)
> special working day > weekday pattern. Nothing is hard-coded: a school that
works Saturdays gets working Saturdays, and branches differ because working
days are per branch.

| Day kind | Teacher | Manager |
|---|---|---|
| Working / special working day | marks normally | marks normally |
| Non-working weekday or holiday | **blocked**, day named | allowed as an **authorized override** with a required reason (stored as `dayKind`/`overrideReason` on the register) |

Dates in the future, and (for students) dates outside the academic year, are
refused outright. The calendar rule is enforced in the client; Firestore
rules cannot look up "is this date a holiday" without a read per date (see
limitations). Attendance documents carry no holiday data.

## Attendance percentage

```
percentage = (present + late + 0.5 × halfDay) ÷ (present + absent + late + halfDay) × 100
```

- `LATE` counts as attended (the person came); `HALF_DAY` as half a day.
- Only **marked** days are in the denominator. Unmarked days, weekends and
  holidays have no record and are not counted. Nothing marked → no
  percentage (shown as "—").
- A report covers one academic year's section (or one student) and the date
  range must lie inside that year, so years are never mixed.

## Dashboard, views and reports

- **`/attendance`** — date + academic year (+ class/section for managers).
  Registers started, finalized, totals, the **pending** sections and the
  staff register, all read from the register documents. Teachers see only
  their own sections. "Enrolled" is the sum over registers already started;
  sections nobody has opened have no count to read and appear only under
  pending.
- **`/attendance/reports`** — students (class/section, or one student) or
  staff (all, or one); date range with This month / Last month; per-person
  Present/Absent/Late/Half day/Marked/% with a day-by-day drill-down.
- **CSV** — "Copy CSV" puts the report on the clipboard (there is no file-
  download dependency). The encoder quotes per RFC 4180, uses CRLF, writes
  numbers as numbers, empty for missing, and prefixes any text cell starting
  with `= + - @ TAB CR` with `'` to defeat spreadsheet formula injection.
  Covered by unit and widget tests; a result is capped at 4,000 records and
  the page says so when it is cut.

## Queries and indexes

| Query | Used by | Index |
|---|---|---|
| `academicRecords` (collection group) `schoolId, branchId, academicYearId, classId, sectionId` all `==` | roster | **composite, COLLECTION_GROUP** |
| `studentAttendance` `academicYearId, classId, sectionId, dateKey ==` | load a register | equality only — merged single-field |
| `studentAttendance` `academicYearId, classId, sectionId ==` + `dateKey` range + order | class monthly report | **composite** (year, class, section, dateKey) |
| `studentAttendance` `studentId ==` + `dateKey` range | one student's history | **composite** (studentId, dateKey) |
| `staffAttendance` `dateKey ==` / `dateKey` range | staff register / report | single-field |
| `staffAttendance` `staffId ==` + `dateKey` range | one staff member | **composite** (staffId, dateKey) |
| `attendanceSessions` `dateKey, academicYearId, [classId, sectionId] ==` | dashboard | equality only |
| `…/history` `orderBy revision` | history dialog | single-field |

Roster cost: one group query (the section's enrollment records, roughly the
class size), N/30 student reads, N attendance reads, 1 day read. Student
queries pin `academicYearId`, `classId` and `sectionId` so a class teacher's
queries satisfy the rules.

## Permissions

New in the existing RBAC (no second system):

| Permission | Platform / School / Branch admin | Teacher | Finance | Parent |
|---|---|---|---|---|
| `viewAttendance` (hub, reports) | yes | yes | yes | no |
| `markStudentAttendance` | yes | yes (own sections only) | no | no |
| `manageAttendance` (staff attendance, finalized corrections, calendar override) | yes | no | no | no |
| `viewStaffAttendance` | yes | no | yes (read) | no |

Routes: `/attendance` (view), `/attendance/students` (mark),
`/attendance/staff` (view staff attendance), `/attendance/reports` (view).

**A TEACHER role grants no class.** A teacher may mark a section only if they
are its **class teacher** (Milestone 4 `CLASS_TEACHER` assignment slot) and
their staff record is `ACTIVE`; subject teachers cannot mark daily
attendance, and a section with no class teacher can only be marked by an
administrator. Parents have no access; the future Parent Portal should read
through the `parentLinks` relationship, as for student data.

## Security rules (summary)

Helpers: `canManageAttendance`, `isClassTeacherOf` (slot → staff →
`userId == auth.uid` + `ACTIVE`), `canMarkStudentAttendance`,
`attendanceSessionKey`, `isFinalizedDay`, `validDateKey`,
`notFutureAttendance`, `validChangeReason`, `validDayCounts`.

- **Tenant/branch isolation** — every collection is judged against the path's
  school/branch and the caller's profile; the doc's own `schoolId`/`branchId`
  must match the path.
- **Student records** — create/update/read for managers of that branch, or
  the class teacher of exactly that year-class-section. Deterministic id,
  revision 1 on create and +1 on update, immutable identity/placement,
  valid status, remarks ≤ 200, date not later than tomorrow, finalized =>
  manager + reason.
- **Registers** — id must match the fields; counts non-negative integers;
  finalization stamped by the caller at server time; a finalized register can
  only be touched by a manager.
- **History** — immutable; actor and time are rule-checked; scope fields must
  be ones the caller may mark.
- **Staff** — managers write; finance reads; a staff member reads only their
  own days; teachers/parents nothing else.
- **Roster** — collection-group read of `academicRecords` follows
  `viewStudentData`, judged on each record's own tenant ids.
- No hard deletes anywhere.

What the rules **cannot** do (each is a documented limitation, not an
oversight): verify per student that they are enrolled in the section (one
read per student, over the 20-document-per-request limit), consult the
calendar, or check the arithmetic of the day counts. There are no Cloud
Functions in this project; a trusted backend operation would close these and
is the recommended hardening if the risk matters.

## Tests

| Layer | What | Where |
|---|---|---|
| Unit | dates/timezone safety, statuses, tally and percentage, calendar (working, public/school/local/special holiday, non-working, special working day, per-branch), enrollment and staff eligibility (transfers, late joiners, leavers), sheet rules (bulk, partial, finalize, corrections), save planner (concurrency, retry/double-save, cross-section, minimal writes), serialization, CSV | `test/attendance/*` |
| Widget | route/nav permissions per role; teacher marking flow, partial confirm, finalize, double-click, success-after-write, conflict, friendly error; finalized lock; holiday block and manager override; staff register incl. finance read-only; dashboard figures; reports (percentages, range guard, CSV via clipboard); mobile/tablet/desktop layout | `test/widget/attendance_*_test.dart` |
| Rules (emulator) | 21 tests: school and branch isolation, class-teacher scope, finance/parent denial, deterministic id, revision, immutables, validation, finalization lock and correction reason, history, whole-class batch, staff attendance, roster query | `firestore-tests/attendance-rules.test.mjs` |

The rules suite was mutation-checked: removing the revision check, the
class-teacher scoping, the finalization lock and the id check each made tests
fail.

## Known limitations

See the final report for the P0–P3 classification. In short:

- The Dart repositories — including the transaction, the collection-group
  roster query and the composite indexes — have not been run against a real
  or emulated Firestore by automated tests; the rules are.
- Enrollment membership, the calendar and the day counts are client-checked
  (see Security rules).
- Only class teachers can mark; there is no per-subject/period attendance.
- No re-open UI, no offline sync, no check-in/out times, `attendanceCutoffTime`
  is unused, "today" is the device date (not the school timezone).
- Dashboard "enrolled" covers started registers only; reports cap at 4,000
  records; student-level reports are manager-only (a teacher's rule scope
  needs a section).
- Parent/Leave/Notification/Payroll consumers are not built; the model leaves
  room (`staffId`/`studentId`-keyed day records, `dateKey`, immutable
  history, no `LEAVE` status).
