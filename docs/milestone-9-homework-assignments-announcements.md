# Milestone 9 — Homework, Assignments & Announcements

Status: **implemented, with documented gaps** (§15). Nothing in Milestone 10 has been started.

## 1. What was assessed first (source is the truth)

Before writing code the repository was read, not assumed:

- **Tenancy and RBAC**: `users/{uid}` profile is the lookup table for Firestore *and* Storage rules (`callerProfile()`); roles are `PLATFORM_ADMIN`, `SCHOOL_ADMIN`, `BRANCH_ADMIN`, `TEACHER`, `FINANCE`, `PARENT`. **There is no student login role** — students are served through their linked parents' portal accounts. "Students/parents" in the brief therefore means the parent portal for a linked child.
- **Teacher authority** already exists as `assignmentSlots/{year}__{class}__{section}__{subject}` (M4) naming the ACTIVE `teacherStaffId`, plus `staff.userId`. Homework authorisation reuses it; no new authority table was invented.
- **Parent ↔ child** is `students/{id}/parentLinks/{parentId}` with `status == ACTIVE` and `canAccessPortal`; `canAccessAsParent` already guards fees/leave. Reused.
- **Placement**: `students.currentAcademicYearId/currentClassId/currentSectionId` (+ `status`) is the enrolment fact used for eligibility.
- **Notifications**: M7's `notifications` collection (USER / REVIEWERS audience, deterministic ids, written in the commit of the event, updatable only to set `readAt`), extended in M8. Reused; extended for two types.
- **Storage**: existing `storage.rules` with `firestore.get()` lookups; extended, not replaced.
- **Timetable**: read-only use of the published timetable to offer "subjects taught today". No timetable, academic, student, parent or attendance code was modified.

## 2. Features

| Area | Delivered |
|---|---|
| Homework | Create one homework per class-section × subject under a shared batch id (idempotent), draft → preview → publish, edit draft, edit instructions/files of a published homework, **extend** the deadline, close, archive; history of every change. |
| Submissions | One submission per child per homework (id `{homeworkId}__{studentId}`); submit, resubmit (before the deadline when permitted, or when returned), late handling by policy, append-only revision history, teacher grade / return for revision / mark reviewed, feedback and marks. |
| Review | Paginated submissions by status, derived "not submitted" list from the roster page by page (never loads a whole class), per-homework counts from aggregate queries. |
| Announcements | Audiences ALL / BRANCH / STAFF / PARENTS / CLASS / SECTION, draft → preview → publish (immediate or scheduled), optional expiry, update of a published one (optionally re-notify), archive (never delete), attachments, author and audit trail. |
| Notifications | In-app only. *Broadcast notices* for publication / deadline change / announcement; *targeted notifications* for returned / graded. No email, SMS or WhatsApp. |
| Files | Firebase Storage, validated type and size, create-only unique paths, Storage rules enforce access. |
| Dashboards | Teacher: draft/published/closed counts, upcoming deadlines, per-homework "to review". Family: to do / overdue / needs revision / submitted / graded, updates, announcements. Admin: counts + filter by class, section, teacher, status. |

## 3. Data model (all under `schools/{s}/branches/{b}/`)

| Collection | Id | Purpose |
|---|---|---|
| `homework` | `{batchId}__{sectionId}` | One per section. Fields: title, description, academicYearId, classId, sectionId, subjectId, teacherStaffId, assignedDateKey, dueDateKey, dueTimeMin, **dueAt** (instant), attachments, maxMarks, requiresSubmission, allowFiles, allowLate, allowResubmission, status, revision, lastEvent, publishedBy/At, audit. |
| `homeworkHistory` | `{homeworkId}__{revision}` | Append-only: event, toStatus, actor, time. |
| `homeworkSubmissions` | `{homeworkId}__{studentId}` | Current state: status, late, textAnswer, attachments, revision, lastEvent, submittedBy/At, feedback, marks, gradedBy/At, reviewedBy/At. |
| `homeworkRevisions` | `{submissionId}__{revision}` | Append-only snapshot of each change (what the student wrote, what the teacher said, by whom). |
| `announcements` | `an_…` | Audience, title, body, attachments, publishAt, expiresAt, status, revision, author, audit. |
| `announcementHistory` | `{announcementId}__{revision}` | Append-only. |
| `broadcastNotices` | `{refId}__{EVENT}__{revision}` | One audience-addressed in-app notice per event. |
| `notifications` (existing) | `{submissionId}__{EVENT}__{revision}` | `HOMEWORK_RETURNED` / `HOMEWORK_GRADED` to the submitter. |
| `users/{uid}/noticeReads/state` | — | The user's own read state (rules only; no UI yet). |

Storage paths (create-only):
- `schools/{s}/branches/{b}/homework/{homeworkId}/files/{file}`
- `schools/{s}/branches/{b}/homework/{homeworkId}/submissions/{studentId}/{file}`
- `schools/{s}/branches/{b}/announcements/{announcementId}/files/{file}`

No download URL is stored; only `path, name, contentType, sizeBytes, uploadedBy, uploadedAt`. A link is minted on demand and only works if the Storage rules allow the caller. No binary is stored in Firestore.

## 4. State machines

**Homework**: `DRAFT → PUBLISHED → CLOSED → ARCHIVED`; `DRAFT → ARCHIVED`. Published: only *instructions/files* and an **extension** of the deadline may change; title, marks, policy, class, section, subject and teacher are fixed once families may have started. Closing stops submissions but grading continues.

**Submission** (stored states; `NOT_SUBMITTED` is derived = no document):
`SUBMITTED | LATE_SUBMITTED → RESUBMITTED → …`, `→ GRADED`, `→ RETURNED_FOR_REVISION → RESUBMITTED`.
- Family may change work in `SUBMITTED/LATE_SUBMITTED/RESUBMITTED/RETURNED_FOR_REVISION` → `RESUBMITTED` (graded work is locked until returned).
- Reviewer: grade (also re-grade), return (reason ≥ 3 chars, clears marks), mark reviewed (no state change).
- Opening a homework records nothing; only a confirmed submit does.

**Announcement**: `DRAFT → PUBLISHED → ARCHIVED`; `DRAFT → ARCHIVED`. Audience is immutable after creation.

## 5. Late and deadline rules

- `dueAt` is computed once from the due date and optional time (end of day if none) **in the publisher's local timezone**, assumed to be the school's.
- Lateness is judged by the rules on the **server clock** (`request.time`) against `dueAt`. A client-claimed time is never used. A submission on time must be `SUBMITTED/late=false`; after the deadline it is accepted only when `allowLate`, as `LATE_SUBMITTED/late=true`.
- A returned submission may be resubmitted even after the deadline (the teacher asked for it); its `late` flag is sticky.
- A deadline can only be extended (shortening would turn on-time work into late work).

## 6. Reporting definitions (applied everywhere)

- A **late** submission counts as handed in *and* in the "late" count.
- `RETURNED_FOR_REVISION` is **not** complete (outstanding).
- `RESUBMITTED` and `GRADED` count as handed in.
- Awaiting review = `RESUBMITTED` + (`SUBMITTED`/`LATE_SUBMITTED` with no `reviewedBy`).
- "Not submitted" is derived from the section's *current* roster of ACTIVE students; students who moved or left are not in the denominator, but their submissions remain readable in the homework's own record.
- Expired announcements are excluded from "current" views and kept in history.

## 7. Access model

| Actor | Homework | Submissions | Announcements |
|---|---|---|---|
| Platform / school admin | all in school | read/grade/return/review | create/publish any audience (ALL: school admin only) |
| Branch admin | own branch | read/grade/return/review | any audience except ALL |
| Teacher | create/edit/publish **only** for a section+subject whose ACTIVE assignment slot names them; reads own drafts and published of the branch | review/grade only for their homework | SECTION only, and only of which they are class teacher |
| Finance | none | none | read published |
| Parent | read PUBLISHED/CLOSED | create/resubmit only for a **linked, portal-enabled, ACTIVE** link to a child **currently placed in that class and section** and ACTIVE; read own child's | read PUBLISHED of parent-addressable audiences |

Platform admin appears with school-admin power by the existing `canManageStaff` pattern.

## 8. What rules enforce — and what they cannot

Enforced by `firestore.rules` / `storage.rules` (emulator-tested, mutation-checked, and with Dart-written documents replayed through the real rules):

- tenant and branch isolation for every collection and path;
- **teacher authority**: the claimed `teacherStaffId` must be the ACTIVE assignment-slot holder for that section+subject, and the caller must be that staff member (or an admin); another subject, another section, or a made-up subject is refused;
- **idempotent creation**: id = `{batchId}__{sectionId}`; free-text ids refused; a replay cannot create a second document;
- the state machine, `revision == previous + 1`, and an append-only history/revision document **in the same commit** for every change;
- publish: draft only, `dueAt > request.time`, the author still holds the slot, and the broadcast notice is written with it; deadline change: extension only, with its notice;
- **submission**: id uniqueness, linked parent, child's current class+section+ACTIVE status, homework PUBLISHED and requiring submission, server-time lateness, content bounds (≤ 3 files, files only if enabled, text ≤ 5000, not empty), and **no marks/feedback/grader fields** from a family;
- **resubmission**: not after the child moved sections or left; before the deadline when permitted (or when returned); graded work locked;
- **grading**: only the homework's teacher or an admin; marks `0..maxMarks` (`null` when ungraded); return needs a reason; reviewer fields set to the caller and server time;
- **announcements**: audience authority (above), history + notice with publish, expiry after start, archive instead of delete, audience immutable;
- **notices**: tied to the event that wrote them (type, revision, section/audience, writer, recipient = submitter); forged or mismatched ones refused;
- **Storage**: create-only (no overwrite, no delete), PDF/JPEG/PNG/TXT/DOCX, `< 10 MB`; teacher/admin write homework files; only a linked parent with an ACTIVE, portal-enabled link writes under their child; teacher reads submission files only for homework they created; drafts' files only for author/admin.

**Not enforceable in rules (honest limits):**

1. **Parent ↔ section for reading.** A rule cannot look a child up by parent. Any ACTIVE parent of the school can read PUBLISHED/CLOSED homework, published announcements and notices of a branch if they know the document id or run the pinned list query; the app shows only the linked child's. Submissions, revisions and private feedback **are** protected by the parent link. Homework attachments are readable by any school parent once published.
2. **Scheduled announcements** cannot be hidden before `publishAt` by list rules (no time-based filter without a query). The app hides them; a hand-built query would see a scheduled announcement's text early.
3. **Teacher-owned homework files via Storage**: Storage rules may make two Firestore lookups, one is the caller's profile. A teacher is recognised by `homework.createdBy == uid`, so when an admin created homework **on a teacher's behalf** that teacher cannot read the submission files through Storage (the admin can; Firestore access is unaffected).
4. **Submission file uploads are not tied to the deadline or enrolment in Storage** (no budget for it). An out-of-policy upload is an *orphan object* no submission references; the Firestore rules still refuse the submission itself.
5. **Orphans**: removing a file from a form removes the reference, not the object (objects are never deleted by clients). Failed multi-file saves can also leave objects. A scheduled cleanup would need a trusted backend.
6. **No malware scanning** of uploaded files. Type/size are validated; content is not.
7. **Timezone**: `dueAt` is the publisher's local instant. A publisher in another timezone than the school sets a different instant.
8. **Clock skew** near the deadline: lateness is the server's decision; a device clock a few minutes off may be shown "submit" and refused (retry succeeds as time passes).
9. **No student login** exists; the portal is the parent's.
10. **No trusted backend**: fan-out (per-recipient notifications), reminders before deadlines, scheduled publication, and cleanup need Cloud Functions. This milestone deliberately avoids unbounded client fan-out by using *broadcast notices* that recipients resolve on read.

**Evaluation budget.** The submission update rule uses roughly 70–85% of Firestore's 1000-expression evaluation budget (measured by padding the rule until the grade batch failed: ~150 spare expressions pass, ~300 fail). Adding conditions there needs offsetting; the rules were refactored to a single profile read (`profileManages`, `profileTeachesHomework`, `profileIsLinkedParent`) for that reason.

## 9. Notifications

- **Broadcast notices** (`broadcastNotices`): homework published, deadline changed, announcement published/updated. One document per event, written in the event's commit with a deterministic id, so a retry cannot duplicate it. Recipients resolve them on read from their own relationships (a parent's children's section; a teacher's teaching sections; branch staff). Carries a title, one line and a reference — never a student's work or feedback.
- **Targeted notifications** (`notifications`): `HOMEWORK_RETURNED` / `HOMEWORK_GRADED` to the submitter (`submittedBy`) in the commit of the review. Body is subject and title only — no marks, no feedback text.
- Expired/archived/draft announcements do not show; an announcement notice appears only once that announcement is current. Inactive accounts cannot read anything (rules). Nothing is sent outside the app.
- Read state per user (`noticeReads`) exists in the rules; the UI currently shows the latest notices without per-item read marking.

## 10. Indexes (14 new, 75 total)

`homework`: (academicYearId, dueDateKey↓), (+teacherStaffId), (+teacherStaffId, status), (+classId), (+classId, sectionId), (+status), (+classId, status), (+classId, sectionId, status); `homeworkSubmissions`: (homeworkId, studentName), (homeworkId, status, studentName); `announcements`: (status, publishAt↓), (status, audienceKind, publishAt↓), (authorId, createdAt↓); `broadcastNotices`: (audienceKind, createdAt↓). Equality-only queries (revisions, history, per-student lookups, aggregate counts) merge single-field indexes. **Not exercised by the emulator** — deploy and watch for "index required". The homework list filters subject client-side on a page (a page can hold fewer than 25 items; `hasMore` is authoritative).

## 11. Screens (all present)

Homework list + dashboard · create/edit (multi-section, timetable quick-pick, files, validation) · publication preview · detail with attachment viewer, counts, history, actions · teacher review (status filters, not-submitted, pagination) · submission details with revision history · grading / return form · family list (states, subject filter, updates, announcements) · family detail with submission form and confirmation · announcement list (current / scheduled / expired / drafts / archived) · announcement create/edit with preview · announcement detail. Every screen has loading, empty, error and validation states, confirmation for destructive/outward actions, semantic labels on status and live-region errors, and lays out at 390 / 820 / 1400 px.

## 12. Tests and results

- **Unit** (`test/homework/homework_domain_test.dart`, 23): validation, publish and deadline-change rules, submit/resubmit/late/closed, content bounds, grading bounds and return, family states, reporting definitions, file policy (incl. exactly-10-MB refusal to match the Storage rule), announcement audience and time.
- **Contract** (`homework_write_contract_test.dart` + `homework-contract.test.mjs`): the exact documents the Dart code writes for homework, submission and announcement lifecycles are replayed through the real rules, step by step (23 batches in three workflows).
- **Widget** (`test/widget/homework_ui_test.dart`, 40): route/permission matrix per role, teacher list/counts/own-only, creation (own sections only; admin any; validation; draft; preview-before-publish; cancelling writes nothing), lifecycle (publish once, close confirmation, published fixed fields), review (marks bounds, grade, return needs reason, not-submitted from roster, withdrawn excluded), family (states, other section hidden, unlinked child, submit needs confirmation and happens once, late policy, returned/graded), announcements (audience filtering, expired/scheduled/draft hidden, manager views, class-teacher limit, preview before publish, branch admin cannot address the school), responsive.
- **Rules** (`homework-rules.test.mjs` 27, `homework-storage-rules.test.mjs` 5, contract 1): tenant/branch isolation, authority, eligibility, late rules, duplicates, resubmission and history, grading, parent-child isolation, link status/portal/role, announcement audiences and states, notice idempotency and forgery, the exact queries the app issues, Storage restrictions.
- **Mutation check**: 34 mutants applied to the rules; **32 killed, 2 equivalent** (the top-level key list of the homework update is redundant with each branch's own list; the notice writer tie is redundant with the update's `updatedBy`). Several first survived — a weak "not their child" test (ran after the document existed), a missing link-status test, a missing role test, a missing revision-skip test, a missing author test, a missing Storage link-status test — and were fixed with tests, then re-killed.
- **Bugs found while building**: the large update rules exceeded the 1000-expression budget (restructured with `let` and profile-based helpers); a homework seed overwrote `createdBy`; an unpinned revision query by a teacher is refused (query now pins the homework); announcement update exhausted the budget for a class teacher (restructured); file policy accepted exactly 10 MB but Storage requires `< 10 MB`; Storage objects persist across tests in the emulator.
- Full: 734 Flutter tests, 226 rules tests (serial).

## 13. Deploy

1. `firebase deploy --only firestore:rules,storage,firestore:indexes` and wait for the indexes.
2. Ensure teacher assignments exist (homework can only be set for assigned section+subject) and class teachers are assigned if teachers should post section announcements.
3. Run the rules suite serially with project id `demo-eazy-school-360`:
   `firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && npm test"`.
4. Regenerate the contract fixture with `flutter test test/homework/homework_write_contract_test.dart` after changing what the Dart code writes.

## 14. Reuse and non-interference

M0–M8 behaviour is unchanged: existing notification rules were left as they were (the new types live in their own match so that rule keeps its headroom), existing Storage paths untouched, and the whole earlier suites (all 193 prior rules tests and 669 prior Flutter tests) still pass. The `PlatformAdmin has every permission` and parent permission tests were updated for the new permissions.

## 15. Known limitations / not verified

1. No end-to-end run against a real Firebase project; the 14 new indexes and the Storage rules' behaviour against production are unexercised (emulator only).
2. §8 items 1–10 are real limits, not omissions: parents are school-wide *readers* of published homework/announcements; scheduled announcements are hidden client-side; teacher file reads depend on `createdBy`; orphaned and unscanned files; timezone and clock-skew assumptions; no backend for fan-out, reminders or scheduled publication.
3. **No student account**; only parents (per the project's roles).
4. **Teacher dashboard** lacks "recently graded" and an announcements strip; non-submitters and awaiting-review are per-homework. **Admin reporting** is counts by status plus filters and per-homework completion — there is no school-wide completion-percentage report.
5. **Bulk grading** is not provided (each submission is graded individually; deemed safer than unaudited bulk writes).
6. An announcement with audience ALL is stored under the selected branch and reaches that branch's people; posting to the whole school means posting in each branch.
7. A "mark all as read" for notices is not implemented.
8. Rich text / images inline in announcements are not supported; images are attachments.
9. A multi-section create is one commit per section; a failure part-way leaves the earlier sections as drafts (retrying is idempotent and reports it).
10. iOS cannot be built here (iOS 26.5 platform not installed).
11. `dashboard_page.dart` still carries its Milestone 1 placeholder sentence about future modules (unchanged — outside this milestone's scope).
