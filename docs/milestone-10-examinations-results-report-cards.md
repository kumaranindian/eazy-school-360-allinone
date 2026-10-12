# Milestone 10 — Examinations, Marks, Report Cards & Academic Performance

Status: **implemented, with documented gaps** (§16). Nothing in Milestone 11 has been started.

## 1. What was assessed first (source is the truth)

- **No assessment code existed.** `grep` for exams, marks, grades, results and report cards found nothing in `lib/`; the only related names were M9's `maxMarks` for *homework* grading, which is unrelated and untouched.
- **Reused as-is**: tenant context and RBAC (`Permission`/`RolePermissions`), `assignmentSlots` (teacher authority, M4), `students.current*` placement cache and `status` (enrolment, M3), `parentLinks` + `profileIsLinkedParent` (parent ↔ child, M3/M9), academic years/classes/sections/subjects/class-subjects (M2), `AttendanceTally` and `StudentAttendanceRepository.fetchStudentRange` (attendance summary, M5), `broadcastNotices` (notifications, M9), `pdf` + `printing` (already in `pubspec.yaml` for fee receipts; web-compatible), `TimetableScope`/`StaffBranchScope`/`FamilyScope`, and the shared page widgets from M9.
- **Roles**: `PLATFORM_ADMIN`, `SCHOOL_ADMIN`, `BRANCH_ADMIN`, `TEACHER`, `FINANCE`, `PARENT`. There is **no "result approver" role and no student login**. Approval is by the two administrator roles (§7); "students" means the parent portal for a linked child.
- **Backend**: none (no Cloud Functions). Everything is client-side under security rules; §9 states what that cannot guarantee.
- **Storage**: not used. Report cards are rendered on the device from the stored result; there is no file and therefore no public URL.

## 2. Features

| Area | Delivered |
|---|---|
| Examinations | Name, description, type (unit test / quarterly / half-yearly / annual / practical / other), academic year, class, one section or all, dates, instructions, grading scheme; per-subject max, passing marks, weightage, date and time, optional theory + practical components. Draft → scheduled → marks entry → finalised → published; withdraw, reopen, cancel with a reason. |
| Grading schemes | Bands (grade, description, minimum %, optional grade point), subject pass %, optional overall pass %, 0–3 decimals, rounding (half-up / down), absent policy (exclude / count as zero), aggregation (total / weighted), ranking on/off. Live validation of overlaps, gaps, duplicates. |
| Marks entry | Roster from current enrolment; status per student (entered / absent / exempted / pending); marks or theory + practical; remark; search and filter; table on tablet/desktop, cards on phone; save draft; submit for review. |
| Review | Per-sheet approve / return with a note; submitter cannot approve (school admin excepted). |
| Calculation | One calculator: subject %, grade, pass/fail; totals; overall %; weighted %; GPA (only when grade points exist); rank (only when enabled); provisional preview before finalisation. |
| Finalise / publish | Immutable, versioned results with the scheme snapshot and an attendance snapshot; publication notifies the class once; withdraw → reopen → corrected new version. |
| Report card | On-screen and PDF (print / download) from the stored result, with remarks, attendance, signature placeholders. |
| Family portal | Linked child's published results, report card, remarks, progress between examinations of the *same* scheme. |
| Performance | Pass rate, average, grade distribution, subject table, students who may need support (admins); teachers see their own subjects only. |
| History | Append-only exam and sheet history with reasons. |

## 3. Data model (all under `schools/{s}/branches/{b}/`)

| Collection | Id | Purpose |
|---|---|---|
| `gradingSchemes` | `gs_…` | Scheme configuration (edited in place with a revision). |
| `examinations` | `{year}__{class}__{section\|ALL}__{name-slug}` | One per scope + name — the id is the duplicate guard. Holds status, revision, `subjectCount`, `sheetCount`, `approvedSheets`, `resultVersion`, `resultCount`, `resultsWritten`, `schemeSnapshot`. |
| `examinationSubjects` | `{examId}__{subjectId}` | Max, pass, weightage, date/time, components. |
| `examHistory` | `{examId}__{revision}` | Append-only: event, to-status, actor, reason. |
| `marksSheets` | `{examId}__{subjectId}__{sectionId}` | Review state of one subject in one section. |
| `marksSheetHistory` | `{sheetId}__{revision}` | Append-only. |
| `marksEntries` | `{sheetId}__{studentId}` | The student's status, marks, components, remark, revision. |
| `marksRevisions` | `{entryId}__{revision}` | Append-only record of every change to an entry. |
| `examRemarks` | `{examId}__{studentId}` | Teacher and principal remarks, typed before finalisation. |
| `resultSummaries` | `{examId}__{studentId}__v{n}` | **Create-only** finalised result: per-subject lines, totals, grade, result, rank, scheme snapshot, attendance snapshot, remarks. |
| `broadcastNotices` (M9) | `{examId}__PUBLISHED__{version}` | `RESULT_PUBLISHED`, one per version. |

Relationships: exam → class/section/year/scheme; subject → exam + class-subject; sheet → exam + subject + section; entry → sheet + student (enrolled in that class + section); result → exam + student + version. Calculated data (totals, grades) is stored only in `resultSummaries`, because a finalised report card must not change when policy or marks later change; nothing is duplicated into other collections.

## 4. State machines

**Examination**: `DRAFT → SCHEDULED → IN_PROGRESS → COMPLETED → PUBLISHED`; `PUBLISHED → WITHDRAWN`; `COMPLETED | WITHDRAWN → IN_PROGRESS` (reopen, reason); `DRAFT | SCHEDULED | IN_PROGRESS → CANCELLED` (reason). Configuration (details, subjects) changes only in `DRAFT`/`SCHEDULED`. Marks change only in `IN_PROGRESS`.

**Marks sheet**: `DRAFT → SUBMITTED → APPROVED`; `SUBMITTED | APPROVED → RETURNED (note) → SUBMITTED`. Approving moves `approvedSheets` by +1 in the same commit; returning an approved sheet moves it by −1.

**Mark status** (per entry): `ENTERED` (marks may be **0**), `ABSENT`, `EXEMPTED`, `PENDING` (not decided). They are different things and are never conflated.

**Correction of a published result** (never an in-place edit): administrator *withdraws* (families lose access at once) → *reopens* with a reason → returns the affected sheet(s) → teacher corrects, resubmits → admin approves → *finalise* creates version n + 1 → *publish*. Earlier versions stay on record, unreadable by families once superseded.

## 5. Calculation rules (`ResultCalculator` — the only place they exist)

For one student and one examination, over the configured subjects:

1. **Entered** marks: `percent = obtained ÷ max × 100`, rounded to the scheme's decimals and rounding mode; the **grade is looked up from the rounded percent**; the subject **passes when `obtained ≥ passing marks`** (the subject's own, else `max × scheme pass % ÷ 100`).
2. **Exempted**: left out of every total; cannot fail.
3. **Absent**: scheme policy — *exclude* (left out of totals; flagged "absent") or *zero* (counted as 0 of the maximum and a failed subject).
4. **Pending / no entry**: the result is **incomplete** and cannot be finalised.
5. **Totals**: `Σ obtained`, `Σ max` over counted subjects. `percentage = Σ obtained ÷ Σ max × 100`.
6. **Weighted**: `Σ(subject % × weightage) ÷ Σ weightage` over counted subjects.
7. **Overall percentage** is the total or the weighted figure per the scheme; the **overall grade** uses the same bands.
8. **Result**: FAIL if any counted subject failed (or an absence under the zero policy) or the overall percentage is below the scheme's overall pass %; PASS otherwise; NOT_APPLICABLE when nothing was counted (never a pass).
9. **GPA**: only when every band carries a grade point — the weightage-weighted mean of subject grade points, 2 decimals.
10. **Rank**: only when the scheme enables it — competition ranking (1, 2, 2, 4) by overall percentage among students who have one.
11. **Rounding** is `(x × 10ᵈ + 1e-9)` then half-up or floor, so 1.005 → 1.01 and recalculation is bit-for-bit identical.

Dashboard definitions: *pass rate* = passed ÷ (passed + failed); *average* = mean of overall percentages (students without one excluded); subject averages use entered marks only (absent/exempted are counted separately, never as zero); *needs support* = overall fail or any failed subject. Different examinations are never compared, except on the family page where the same grading scheme is a precondition.

## 6. Attendance summary

Taken at finalisation from the existing attendance records of the child, from the academic year's start to the finalisation date, using `AttendanceTally`: `(present + late + ½ × half-day) ÷ (present + absent + late + half-day) × 100`, over **marked** days only (unmarked days, weekends and holidays are not in the denominator). A child with no marked days shows "no attendance recorded", not 0%. It is a snapshot: later attendance corrections do not alter a published report card. Failure to read attendance leaves the snapshot empty rather than blocking results.

## 7. Authorisation (RBAC)

| Actor | Exams / schemes | Marks | Review / finalise / publish | Results |
|---|---|---|---|---|
| Platform / school admin | configure, open marks entry, cancel, withdraw, reopen | any section; may approve own | approve, return, finalise, publish | all |
| Branch admin | same, own branch | any section; **cannot approve own** | same | all (own branch) |
| Teacher | read | **only a section + subject whose ACTIVE assignment slot names them**; enrolled students only; only while marks entry is open and the sheet is editable | none | published results of the branch |
| Class teacher | — | — | — | teacher remark for own section (not the principal remark) |
| Finance | none | none | none | none |
| Parent | read published examinations of the school | none | none | **only a linked, portal-enabled, ACTIVE child's result, only while PUBLISHED, only the version in force**, fetched by id |

## 8. What the rules enforce

Verified in `exam-rules.test.mjs` (21), `exam-contract.test.mjs` (1: the exact documents the Dart code writes, replayed through the rules, 30 commits across the whole lifecycle including correction) and **mutation-checked (42 mutants)**:

- tenant/branch isolation; only administrators configure, schedule, open entry, finalise, publish, withdraw, reopen, cancel;
- examination id = scope + name (duplicates impossible), valid dates/type, section exists;
- subject: belongs to the class, `0 < pass ≤ max`, weightage > 0, components add up, counter moves in the same commit, only while configurable;
- state machine with `revision + 1` and a history record on every change; reasons required for withdraw, reopen, cancel and sheet return;
- **finalise**: every sheet approved, next result version, scheme snapshot, `resultsWritten` starts at 0; **publish**: results written == count, and the `RESULT_PUBLISHED` notice (one id per version) in the same commit; a retry cannot duplicate it;
- **marks**: assigned teacher or admin only; student ACTIVE and in that academic year + class + section; examination in marks entry and sheet editable; `0 ≤ marks ≤ max`, absent/exempted/pending carry no marks; components sum to the total; a revision record per change; never deleted; frozen in every state but marks entry (administrators included);
- **review**: approver ≠ submitter unless school admin; approval/return move the exam counter with the sheet; return needs a note;
- **results**: create-only, id includes the version, only while COMPLETED and for the version in force; never updated or deleted; parents read only a linked child's, only when PUBLISHED and the version matches; marks, sheets, remarks and history are never readable by parents;
- remarks: class teacher may write the teacher remark only (create and update), administrators both, only during marks entry.

## 9. What rules cannot do (honest limits — a trusted backend is needed)

1. **Arithmetic.** Rules cannot sum a list or recompute percentages and grades. Totals, grades and results in `resultSummaries` are written by the administrator's client from the single calculator, with the scheme snapshot stored beside them. A *modified* client run by an administrator could write wrong figures. Recomputing on finalise needs Cloud Functions.
2. **Completeness counters.** `resultsWritten == resultCount` and "every student has a decided entry" are client-maintained: rules cannot count documents. The calculator refuses incomplete results and `ExamRules.checkPublish` checks the counter, but a modified administrator client could publish with results missing.
3. **Sheet submission completeness.** A teacher's submit is checked by the client (every student decided); rules cannot count entries, so a modified client could submit an incomplete sheet. Finalisation still refuses incomplete results.
4. **Reads by teachers.** A teacher of the branch can read *any* published result of the branch (rules cannot tie a teacher's read to their classes without per-document lookups). The app narrows performance figures to their subjects.
5. **Reads by parents of examination configuration.** Any parent of the school can read a PUBLISHED examination and its subject configuration (title, dates, maxima). Results, marks and remarks are protected by the parent link.
6. **Notifications.** One audience notice per publication (class or section), shown in Announcements → Recent updates for the right audience. No per-recipient notification, push, email or SMS.
7. **Report card generation is not audited**; the PDF is rendered on the viewer's device.
8. **Entry batches are not atomic.** Marks are written five entries per commit (each carries an enrolment lookup); a failure part-way leaves a saved partial draft, never a submitted sheet.
9. **Expression budget.** Firestore's 1000-expression budget limits each rule; the examination update rule and the marks-entry rule were built with `let`-bound profile reads (see M9 notes). Five entries per commit were verified; larger batches were not attempted.
10. **School-wide results for platform support** are not a separate role.

## 10. Report cards

`ReportCardPdf.build` prints only from the stored `ResultSummary` (names, marks, grades, status, totals, remarks, attendance snapshot, scheme name and result version). Provisional previews are labelled in red. Built-in PDF fonts are used (no network or bundled font), so the PDF is **Latin-1 text only**; student names in other scripts will not render in the PDF (they do on screen) — the same constraint as the fee receipts. Print (`Printing.layoutPdf`) and download/share (`Printing.sharePdf`) work on web, Android and iOS. Loading and error states are shown while it is built. There is no URL: access is exactly the Firestore read control on the result document.

## 11. Screens (12 required, all present)

Examination list · create/edit · detail with subject and marks configuration · grading scheme management and editor · marks entry (table / cards) · marks review and approval · result calculation preview and finalisation · publication (confirmation, withdraw, reopen) · student result and report card · report card preview with print/download · academic performance · history and audit. Parent: results list, result + report card. Each has loading, empty, error and validation states, confirmations for finalise / publish / withdraw / reopen / cancel, semantic labels, and lays out at 390 / 820 / 1400 px.

## 12. Indexes (5 new, 80 total)

`examinations`: (academicYearId, startDateKey↓), (+classId), (+status), (+classId, status); `resultSummaries`: (examId, version, studentName). Equality-only queries (entries by sheet, sheets by exam, history, published exams of a class) merge single-field indexes. **Not exercised by the emulator** — deploy and watch for "index required".

## 13. Tests and results

- **Unit** (`test/exams/exam_domain_test.dart`, 40): scheme validation (overlap, missing 0%, duplicates, grade points), examination and subject validation, marks validation (zero, absent, exempted, bounds, components), calculation (totals, weighted, rounding, absent policies, exempted, incomplete, GPA, overall pass %), ranking ties, statistics, workflow rules, self-approval, attendance snapshot, report card PDF generation, result round-trip.
- **Contract** (`exam_write_contract_test.dart` + `exam-contract.test.mjs`).
- **Widget** (`test/widget/exam_ui_test.dart`, 41): route/permission matrix per role, list and configuration, subject validation, scheduling and opening marks entry with confirmation, cancellation reason, scheme overlap, marks entry (maximum, zero, absent/exempted, pending blocks submit, read-only, search, components, phone), review (approve, self-approval blocked, return), results (provisional, incomplete, finalise + publish with attendance and scheme snapshots), report card, withdraw/reopen, history, family (published only, withdrawn disappears, other child, other section, left school), performance, responsive.
- **Rules**: 22 new tests; **42 mutants applied, 40 killed, 2 equivalent** (the approver's `profileManages` is redundant with the counter requirement; the notice revision is redundant with the notice id). Eight mutants first survived — class of the student, state of the exam for sheet changes, "only administrators", the subject counter, a zero maximum, the principal remark on first write, and others — each exposed a missing test and was fixed.
- **Bugs found while building**: calculator crashed on an entry with components but no stored total; a "Result" tile overflowed on narrow screens; a class-subject list read before it had loaded left the subject dialog empty; the report card PDF used glyphs the built-in font lacks; test helpers silently ignored mis-shaped overrides.
- Full: 817 Flutter tests, 248 rules tests (serial).

## 14. Deploy

1. `firebase deploy --only firestore:rules,firestore:indexes` and wait for the indexes. No Storage change.
2. Create a grading scheme (nothing is assumed), then examinations; subject assignments must exist for teachers to enter marks.
3. Run the rules suite serially with project id `demo-eazy-school-360`; regenerate `fixtures/exam-write-plans.json` with `flutter test test/exams/exam_write_contract_test.dart` after changing what the Dart code writes.

## 15. Regression

All Milestone 0–9 suites pass unchanged (the M9 notice rule was extended with one branch; `role_permissions_test` was updated for the new permissions).

## 16. Known limitations / not verified

1. §9 is a list of real limits: arithmetic, completeness counters and sheet completeness are client-verified; teachers can read published results branch-wide; parents can read published examination configuration school-wide.
2. No end-to-end run against a real Firebase project; the 5 new indexes and the rules in production are unexercised.
3. **No student login**; no separate "result approver" role (administrators approve).
4. **Families**: only the child's current class and section are listed; results from a previous class are not looked up (no class-history lookup was added). The year filter is therefore the child's current year.
5. **Cross-examination weighting** (term aggregates across several examinations) is not implemented; "weighted components" are subject weightage and theory/practical.
6. **Dashboards** are lists plus counts of the loaded page, the performance screen, and the family results page; there is no pre-aggregated cross-examination administrator dashboard and no "pending marks entry per teacher" summary beyond each examination's sheet list.
7. Report cards are Latin-1 only (PDF); no branding image/logo; signature *placeholders*, no digital signatures.
8. Remarks are a single teacher and a single principal remark per examination.
9. iOS cannot be built here (iOS 26.5 platform not installed).
10. `dashboard_page.dart` still carries its Milestone 1 placeholder sentence (unchanged, outside scope).
