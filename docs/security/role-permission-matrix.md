# Role & permission matrix

Two layers, deliberately separate:

1. **UI permissions** (`lib/core/permissions/role_permissions.dart`, table below) decide what the app *shows*. Nothing outside that file branches on a role name. This table is generated: `python3 tool/gen_permission_matrix.py`.
2. **Firestore / Storage rules** (`firestore.rules`, `storage.rules`) decide what is *allowed*, from the caller's `/users/{uid}` profile and relationship records — never from email, phone, claims or anything the client sends. Changing layer 1 never grants data access.

## Roles in the application

| Role (wire value) | Implemented | Scope in rules | Notes |
|---|---|---|---|
| `PLATFORM_ADMIN` | yes | every school (see finding H1) | Platform operator. No UI beyond the normal shell. |
| `SCHOOL_ADMIN` | yes | own school, all branches | Manages everything incl. login access and school auth settings. |
| `BRANCH_ADMIN` | yes | own school + own branch | Same powers as school admin inside the branch, cannot manage admins. |
| `FINANCE` | yes (accountant) | own branch, read students/academic setup/staff; fees | No student/staff writes. |
| `TEACHER` | yes | own branch + relationships | Staff record (`staff.userId`), assignments, class-teacher slots. |
| `PARENT` | yes | own school; own child via `parentLinks` + `parentAccess` | Never lists students; reads only linked children. |
| Principal / Academic admin | **no** | — | Covered by `BRANCH_ADMIN`/`SCHOOL_ADMIN`. A separate role is *not* needed until a school wants academic-only powers; add via MULTI_TENANT_GUIDE "How to add a new role". |
| Non-teaching staff, delivery staff, custom roles | **no** | — | Non-teaching staff have staff records but no login unless given `FINANCE`. |

Granular permissions (names in your brief → what exists):

| Brief | Implemented as |
|---|---|
| STUDENT_VIEW / STUDENT_UPDATE | `viewStudentData` / `manageStudentData` |
| ATTENDANCE_VIEW / CREATE / UPDATE | `viewAttendance` / `markStudentAttendance` / `manageAttendance` |
| HOMEWORK_VIEW / MANAGE | `viewHomework`, `viewOwnHomework` / `manageHomework`, `reviewSubmissions` |
| RESULTS_VIEW / MANAGE | `viewExams`, `viewOwnResults` / `manageExams`, `enterMarks`, `approveResults` |
| FEES_VIEW / FEES_MANAGE / PAYMENT_RECORD | `viewFees`, `viewOwnChildFees` / `manageFeeStructures`, `assignFees`, `issueInvoices`, `grantConcessions`, `voidInvoices` / `collectPayments`, `reversePayments` |
| ANNOUNCEMENT_VIEW / MANAGE | `viewAnnouncements` / `manageAnnouncements` |
| STAFF_MANAGE | `manageStaff` |
| USER_ACCESS_MANAGE | `manageUsers` (+ server-side `setLoginAccess`) |
| SCHOOL_SETTINGS_MANAGE | `manageSchool` |

## UI permission table (generated)

| Permission | Platform | School admin | Branch admin | Finance | Teacher | Parent |
|---|---|---|---|---|---|---|
| `adjustLeaveBalances` | ✔ | ✔ | ✔ |  |  |  |
| `approveResults` | ✔ | ✔ | ✔ |  |  |  |
| `assignFees` | ✔ | ✔ | ✔ | ✔ |  |  |
| `collectPayments` | ✔ | ✔ | ✔ | ✔ |  |  |
| `enterMarks` | ✔ | ✔ | ✔ |  | ✔ |  |
| `grantConcessions` | ✔ | ✔ | ✔ |  |  |  |
| `issueInvoices` | ✔ | ✔ | ✔ | ✔ |  |  |
| `manageAcademicSetup` | ✔ | ✔ | ✔ |  |  |  |
| `manageAnnouncements` | ✔ | ✔ | ✔ |  | ✔ |  |
| `manageAttendance` | ✔ | ✔ | ✔ |  |  |  |
| `manageBranches` | ✔ | ✔ |  |  |  |  |
| `manageExams` | ✔ | ✔ | ✔ |  |  |  |
| `manageFeeStructures` | ✔ | ✔ | ✔ |  |  |  |
| `manageHomework` | ✔ | ✔ | ✔ |  | ✔ |  |
| `manageLeaveTypes` | ✔ | ✔ | ✔ |  |  |  |
| `manageOwnProfile` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `managePlatform` | ✔ |  |  |  |  |  |
| `manageSchool` | ✔ | ✔ |  |  |  |  |
| `manageStaff` | ✔ | ✔ | ✔ |  |  |  |
| `manageStudentData` | ✔ | ✔ | ✔ |  |  |  |
| `manageSubstitutions` | ✔ | ✔ | ✔ |  |  |  |
| `manageTimetable` | ✔ | ✔ | ✔ |  |  |  |
| `manageUsers` | ✔ | ✔ | ✔ |  |  |  |
| `markStudentAttendance` | ✔ | ✔ | ✔ |  | ✔ |  |
| `publishTimetable` | ✔ | ✔ | ✔ |  |  |  |
| `reversePayments` | ✔ | ✔ | ✔ |  |  |  |
| `reviewLeave` | ✔ | ✔ | ✔ |  |  |  |
| `reviewSubmissions` | ✔ | ✔ | ✔ |  | ✔ |  |
| `useMessages` | ✔ | ✔ | ✔ |  | ✔ | ✔ |
| `viewAcademicSetup` | ✔ | ✔ | ✔ | ✔ | ✔ |  |
| `viewAnnouncements` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `viewAttendance` | ✔ | ✔ | ✔ | ✔ | ✔ |  |
| `viewExams` | ✔ | ✔ | ✔ |  | ✔ |  |
| `viewFeeReports` | ✔ | ✔ | ✔ | ✔ |  |  |
| `viewFees` | ✔ | ✔ | ✔ | ✔ |  |  |
| `viewHomework` | ✔ | ✔ | ✔ |  | ✔ |  |
| `viewLeave` | ✔ | ✔ | ✔ |  |  |  |
| `viewLeaveCalendar` | ✔ | ✔ | ✔ |  | ✔ |  |
| `viewLeaveReports` | ✔ | ✔ | ✔ |  |  |  |
| `viewNotifications` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `viewOwnChildFees` | ✔ |  |  |  |  | ✔ |
| `viewOwnHomework` | ✔ |  |  |  |  | ✔ |
| `viewOwnLeave` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `viewOwnResults` | ✔ |  |  |  |  | ✔ |
| `viewOwnStaffProfile` | ✔ |  |  | ✔ | ✔ |  |
| `viewOwnTimetable` | ✔ | ✔ | ✔ |  | ✔ | ✔ |
| `viewStaff` | ✔ | ✔ | ✔ | ✔ |  |  |
| `viewStaffAttendance` | ✔ | ✔ | ✔ | ✔ |  |  |
| `viewStudentData` | ✔ | ✔ | ✔ | ✔ | ✔ |  |
| `viewTimetable` | ✔ | ✔ | ✔ |  |  |  |
| `viewUsers` | ✔ | ✔ | ✔ | ✔ | ✔ |  |
| `voidInvoices` | ✔ | ✔ | ✔ |  |  |  |

## What the rules enforce (data access by collection)

`S` = own school only, `B` = own branch only. "own" = found through a relationship record, not a client field.

| Data | Admins (S/B) | Finance (B) | Teacher (B) | Parent |
|---|---|---|---|---|
| `/users/{uid}` | read/write subordinates in scope; **no `login` writes** | self | self (profile fields only) | self (profile fields only) |
| school, branch docs | read; admin write | read | read | read |
| academic years / classes / sections / subjects | read/write | read | read | a **single** `academicYears/{id}` doc (child's branch); no lists |
| students, academicRecords | read/write | read | read (whole branch — see M2) | **only** linked, portal-enabled child (`canAccessAsParent`) |
| parents, parentLinks | read/write | read | read | own record / own links only |
| parentAccess (index) | read/write | read | read | own only; **server/admin written** |
| staff | read/write | read | **own record only** | — |
| teacherAssignments | read/write | — | own (any status) + **ACTIVE of the branch** | — |
| assignmentSlots | read/write | — | — | — |
| attendance sessions / records | read/write | — | class teacher of that section | — |
| fees (structures, invoices, payments, receipts) | read/write | read/write | — | own child's invoices, payments, receipts, assignments |
| leave | review/manage | — | own staff leave; student leave calendar | own child's applications |
| timetable, substitutions | read/write | read | read (live) | child's section only (`parentAccess`) |
| homework, submissions | read/write | — | own homework + its submissions | child's class/section; own child's submissions |
| announcements, broadcastNotices | read/write | read | read (branch) | `ALL`; other audiences need `parentAccess` (M1) |
| exams, marks, results | read/write | — | exam list; marks for assigned section+subject; published results | child's class/section; published, own child's result |
| conversations | participants only | — | participants only | participants only |
| `authSettings`, `authAudit` | school admin read; **server write only** | — | — | — |
| `otpChallenges`, `otpRate` | nobody (server only) | — | — | — |
| everything else | **default deny** (`match /{document=**}`) | | | |

The rules test suite proves each cell with an allowed and a denied case (`firestore-tests/*.test.mjs`; 300+ tests, see `docs/security/rbac-audit.md` §Tests).
