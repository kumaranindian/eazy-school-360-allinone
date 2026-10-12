# Milestone 2 — School Setup & Academic Configuration

This is the detailed reference for Milestone 2. `PROJECT_ARCHITECTURE.md`,
`FIRESTORE_ARCHITECTURE.md`, and `SECURITY_ARCHITECTURE.md` each have a
short pointer here rather than duplicating this content.

## What this milestone builds

The master configuration every future module (Student Management, Fees,
Attendance, ...) will read from: School Profile, Branch Management,
Academic Year, Classes, Sections, Subjects (+ class-subject association),
Working Days, Holiday Calendar, a small Academic Settings document, and a
computed Setup Status checklist. Nothing from Student/Staff/Attendance/
Fees/Leave/Homework/Reports is implemented — those are explicitly future
milestones.

## Collections

All nested under `/schools/{schoolId}/branches/{branchId}/...` — see
"Why nested here but `/users` is flat" in `FIRESTORE_ARCHITECTURE.md`.
Classes, sections, subjects, and holidays are additionally scoped to a
specific academic year, since a class in 2026-2027 and the
same-named class in 2027-2028 are different documents with independent
rosters.

```
/schools/{schoolId}                                                    (extended — see below)
/schools/{schoolId}/branches/{branchId}                                (extended — see below)
/schools/{schoolId}/branches/{branchId}/academicYears/{academicYearId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}/sections/{sectionId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/classes/{classId}/classSubjects/{subjectId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/subjects/{subjectId}
/schools/{schoolId}/branches/{branchId}/academicYears/{yearId}/holidays/{holidayId}
/schools/{schoolId}/branches/{branchId}/settings/workingDays
/schools/{schoolId}/branches/{branchId}/settings/academic
```

## Models (extended or new)

### `School` — extended (`lib/features/school_setup/domain/school.dart`)

Added `shortName`, `code`, `alternatePhone`, `website`, `addressLine1/2`,
`postalCode`, `defaultBranchId`. The single `address` string field from
Milestone 1 was replaced with the structured address fields the brief
asked for — there were no real schools using the old field yet (Milestone
1's self-signup never populated it), so this was a clean extension, not a
migration.

### `Branch` — extended (`lib/features/school_setup/domain/branch.dart`)

Added `email`, `addressLine1/2`, `city`, `state`, `country`, `postalCode`,
replacing the old single `address` field the same way.

### New, in `lib/features/academic_setup/domain/`

| Model | Key fields | Notes |
|---|---|---|
| `AcademicYear` | name, startDate, endDate, status (DRAFT/ACTIVE/CLOSED) | One ACTIVE year per branch, enforced by the repository (see Validation below) |
| `SchoolClass` | name, code, displayOrder, status | Named `SchoolClass`, not `Class`, purely to avoid confusion with the Dart keyword in prose |
| `Section` | name, code, capacity (optional), status | `capacity` is informational only — no student allocation exists yet |
| `Subject` | name, code, shortName, type (CORE/ELECTIVE/LANGUAGE/ACTIVITY/OTHER), displayOrder, status | A catalog per academic year, not per class |
| `ClassSubjectLink` | subjectName/code/type (denormalized), createdAt/By | Doc id *is* the subjectId — a subject can only be linked to a class once, by construction. Create/delete only, never edited in place (see rules below) |
| `Holiday` | date (normalized to midnight UTC), name, type (PUBLIC/SCHOOL/LOCAL/SPECIAL), description, status | |
| `WorkingDays` | `Map<Weekday, bool>` | One singleton doc per branch, not per year |
| `AcademicSettings` | currentAcademicYearId, attendanceCutoffTime, timezone, dateFormat, currency | Deliberately small — see "Why no `schoolWorkingDays` field" below |
| `SetupStatus` / `SetupItem` | label, isComplete, isRequired | Computed, never stored — see Setup flow below |

### `ActivationStatus` (`lib/core/constants/activation_status.dart`)

One shared ACTIVE/INACTIVE enum reused by `SchoolClass`, `Section`,
`Subject`, and `Holiday` — those four entities all have identical
activate/deactivate semantics, so one enum instead of four near-identical
ones. `AcademicYear` keeps its own richer status (DRAFT/ACTIVE/CLOSED) and
`School`/`Branch` keep their own pre-existing status types.

## Relationships

```
School 1---* Branch 1---* AcademicYear 1---* SchoolClass 1---* Section
                                          |                1---* ClassSubjectLink *---1 Subject
                                          1---* Subject
                                          1---* Holiday
                Branch 1---1 WorkingDays
                Branch 1---1 AcademicSettings
```

`ClassSubjectLink` is the many-to-many join between `SchoolClass` and
`Subject` within one academic year — see "Class-subject association"
below for why it's a reference, not a duplicated `Subject` document.

## Permissions

Two new entries in `lib/core/permissions/permission.dart`, granted in
`role_permissions.dart`:

| Role | `manageAcademicSetup` | `viewAcademicSetup` |
|---|---|---|
| PLATFORM_ADMIN | ✓ | ✓ |
| SCHOOL_ADMIN | ✓ (any branch in their school) | ✓ |
| BRANCH_ADMIN | ✓ (own branch only) | ✓ |
| TEACHER | — | ✓ (own branch only) |
| FINANCE | — | ✓ (own branch only) |
| PARENT | — | — |

School Profile and Branch management keep their **existing** Milestone 1
permissions (`manageSchool`, `manageBranches` — school/platform admin
only) rather than the new `viewAcademicSetup` — see "Routing" below for
why.

As with every permission in this app, this table is a **UX-layer mirror**
of `firestore.rules`, which independently enforces the same boundaries —
see `SECURITY_ARCHITECTURE.md`.

## Routing

```
/school                      (unchanged from Milestone 1 — now editable)
/settings                    SettingsOverviewPage (checklist + nav cards)
/settings/branches
/settings/academic-years
/settings/classes            (has its own academic-year selector)
/settings/sections           (has its own academic-year + class selectors)
/settings/subjects           (has its own academic-year selector)
/settings/working-days
/settings/holidays           (has its own academic-year selector; list/calendar toggle)
```

Flat, matching the brief's suggested routes — the "which academic year"
question is answered by a dropdown inside each page (defaulting to the
most recently started year), not a URL segment. School Profile stays at
its Milestone 1 path `/school` (upgraded in place with edit capability)
rather than moving to `/settings/school`, specifically to avoid touching
the route path, nav label, and permission gate that Milestone 1's
passing regression tests already assert on — see
`test/widget/app_router_test.dart`.

`academicSetupRoutes()` (`lib/features/academic_setup/presentation/academic_setup_routes.dart`)
holds the `/settings/*` route list so `app_router.dart` stays a short,
top-level composition rather than growing by one import+line per
sub-page — the brief's "don't create a huge routing file" instruction.

## Security rules

`firestore.rules` gained `canManageAcademicSetup(schoolId, branchId)` and
`canViewAcademicSetup(schoolId, branchId)` helpers (same lookup-table
pattern as everything else — see `SECURITY_ARCHITECTURE.md`), plus one
`match` block per collection above, each:

- scoping reads/writes to the caller's own school (admins) or own
  school+branch (branch admin/teacher/finance),
- requiring `schoolId`/`branchId`/`academicYearId`/`classId` on the
  written document to match the path it's being written to (so a client
  can't, say, write a class under Branch A's path while claiming
  `branchId: "branch-B"` in the document body),
- enforcing server timestamps and caller-matched audit actor fields via
  `validCreateAudit()`/`validUpdateAudit()`,
- restricting updates to the exact field set each role may touch via
  `changedOnly([...])`.

`ClassSubjectLink` is create/delete only (`allow update: if false`) —
re-linking means deleting and recreating, not patching a stale
denormalized snapshot in place.

**Bug found and fixed during this milestone's own validation**: the
`academicYears`/`settings` rule blocks were initially written as
*siblings* of `branches/{branchId}` instead of *children* of it — a
structural nesting mistake that made every Milestone 2 collection
invisible to its intended rules and fall through to the default-deny
fallback (i.e., completely inaccessible, not insecure — but also not
functional). Caught immediately by the rules test suite
(`firestore-tests/rules.test.mjs`) failing with `permission-denied`
pointing at the fallback rule's line number, not a passing-when-it-
shouldn't-have result. Fixed by nesting correctly; all 29 Firestore rules tests
pass against the corrected structure. This is exactly why the brief's
"Firestore Security Rule Tests" step isn't optional busywork — it would
have shipped a feature that silently didn't work at all.

`storage.rules` (the school logo path) is covered by 7 more tests in
`firestore-tests/storage-rules.test.mjs`, run against both the Firestore
and Storage emulators together — `storage.rules` calls
`firestore.get()` to look up the caller's profile, the same lookup-table
pattern used everywhere else. Getting that cross-service call to resolve
in tests required one non-obvious fix: `firebase.json` sets
`"singleProjectMode": true`, which coerces every emulator operation
(regardless of what `projectId` a test file passes to
`initializeTestEnvironment`) onto whatever project the `--project` flag
on the CLI specifies — so the Firestore and Storage test files, and the
`firebase emulators:exec --project` invocation, must all agree on one
project id, or the cross-service lookup silently fails closed (every
"should succeed" case fails, every "should fail" case correctly still
fails, which is a telltale sign of this specific issue — the checks
resolve to false/deny, never incorrectly to true). Documented in
`DEVELOPMENT_GUIDE.md` so the exact command is always correct.

## Queries & indexes

Every list query in this milestone orders by a single field
(`startDate`, `displayOrder`, `name`, or `date`) with no additional
`.where()` filters beyond path scoping — Firestore auto-indexes
single-field queries, so **no `firestore.indexes.json` entries were
needed**. The one exception, duplicate-date checking for holidays
(`.where('date', isEqualTo: ...)`), is also single-field. If a future
change adds a compound query (e.g. "classes where status == ACTIVE,
ordered by displayOrder"), that's the trigger to create
`firestore.indexes.json` — not before.

## Validation (where it's enforced, and why)

Duplicate-name/code prevention (classes, sections, subjects), the
overlapping-active-year guard, and start/end date ordering are enforced
in **`FirebaseAcademicStructureRepository`** (a pre-write read-then-check,
throwing `ValidationFailure`), not in `firestore.rules`. This is a
deliberate split: these are **data-quality** concerns ("don't let two
classes share a name"), not **tenant-isolation** concerns — and
efficiently checking "does any sibling document have this name" isn't
something Firestore rules can do without reading the whole collection on
every single write. Tenant/role authorization for every one of these
writes is still enforced server-side by rules, same as everywhere else.

## School creation / logo upload

School logo upload (`SchoolRepository.uploadSchoolLogo`) uses Firebase
Storage at a **fixed path** (`schools/{schoolId}/logo.{ext}`), so
re-uploading always replaces the previous file instead of accumulating
orphaned ones. File type/size are validated client-side
(`Validators.imageFile` — jpg/jpeg/png/webp, 2MB max) before any upload is
attempted; Storage errors are mapped through the same `error_mapper.dart`
as everywhere else, never shown raw. `storage.rules` now has a real rule
for `schools/{schoolId}/{fileName}`, mirroring `firestore.rules`' same
lookup-table pattern via `firestore.get()` (read: same-school; write:
`manageSchool` holders only, with a server-side size/content-type check
mirroring the client-side validator) — everything else in the bucket
remains default-deny.

## Setup flow

`setupStatusProvider` (`lib/features/academic_setup/presentation/providers/setup_status_provider.dart`)
recomputes `SetupStatus` from the real collections on every read — never
a cached `setupComplete: true` flag that could drift from reality (e.g.
after someone deletes their only class). Required items: School Profile,
Branch, Academic Year, Classes, Sections, Subjects, Working Days.
Optional: Holiday Calendar. The brief's explicit instruction — don't
block the app on every item being done — is honored: `SettingsOverviewPage`
shows the checklist but never prevents navigating anywhere else.

## Class-subject association

A class never duplicates a full `Subject` document. `ClassSubjectLink`
stores only a denormalized display snapshot (name/code/type) alongside
the relationship, keyed by `subjectId` as the document id — so the UI can
render a class's subject list without an N+1 fetch per subject, while the
`Subject` document itself remains the single source of truth for
anything beyond display (status, display order, ...). This is also the
shape a future "teacher-subject assignment" feature would extend: a
`classId` + `subjectId` pair is already the natural key to attach a
`teacherId` to.

## Known issues (Milestone 2)

- **No Dart-level repository tests** (e.g. "duplicate class name is
  rejected") — covered indirectly by the Firestore rules tests (which
  prove authorization) and by model-level unit tests (which prove
  serialization), but the actual duplicate-prevention *logic* in
  `FirebaseAcademicStructureRepository` has no fake-Firestore test
  harness. Adding one would mean a new dependency
  (e.g. `fake_cloud_firestore`) — deferred rather than added under time
  pressure; tracked as a P2 in the final report.
- **Class-subject management and the "Manage subjects" action are gated
  behind `manageAcademicSetup`** — a teacher/finance user with
  `viewAcademicSetup` can see a class's subject *list* nowhere in this
  milestone's UI (only admins can open the association dialog). A
  read-only view for viewers is a reasonable follow-up, not built here.
- **No pagination** on any list (branches, academic years, classes,
  subjects, holidays) — acceptable at the scale a single school/branch
  actually has (tens, not thousands, of classes/subjects), but called out
  since the brief asked for pagination "where appropriate."
