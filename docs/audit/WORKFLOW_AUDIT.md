# End-to-end workflow audit

Audit date 2026-10-31 · read-only · no running app, emulator UI session or dev/prod project was driven by hand. A workflow is **verified step by step by the tests named below** (widget tests with fake repositories, write-plan contract fixtures replayed against the real rules in the emulator, and rules tests). That is strong evidence for logic and authorization, and **no evidence** for network behaviour, Cloud Function triggers, push delivery, or real browsers/devices.

Result key: ✔ covered by named automated tests · ◐ partly covered · ✘ not covered · – not applicable.

## Workflow A - New student admission and parent login
| Step | Covered | Evidence |
|---|---|---|
| 1 Admin creates student | ✔ | `test/students/individual_registration_test.dart` (wizard, validation, duplicate parent checks), `admission-number-rules` |
| 2 Class and section assigned | ✔ | placement step; `academicRecords` rules |
| 3 Parent linked (new, existing, or later) | ✔ | wizard tests, `parent-scope` rules, `AdmissionOutcome` messaging when a link fails |
| 4 Parent login provisioned | ◐ | `functions/provision.test.js` with fakes; UI dialog tests use a fake provisioner. Auth Admin SDK path not run |
| 5 Parent signs in | ◐ | rules gate `loginAllowed()` tested; real sign-in not exercised |
| 6 Parent sees only their child | ✔ | `parent-scope`, `parent-attendance-rules`, `parent-leave-results`, tenant sweeps |

Failure/edge cases covered: duplicate email refused, phone-only match asks, parent save failure keeps the student and reports it, admission-number race (retry on "already in use"), invalid inputs. **Gaps:** the parentAccess/teacherAccess triggers and the callable run in Cloud Functions, which no test starts together with the app; sheet re-upload creates duplicates (PB-05).
**Verdict: PARTIAL.**

## Workflow B - Fee collection
| Step | Covered | Evidence |
|---|---|---|
| 1 Fee structure created | ✔ | `fees-rules`, `fee_structure` form tests |
| 2 Fees assigned to class/student | ✔ | `AssignmentPlanner` tests (skips existing, inactive) |
| 3 Invoices generated | ✔ | `InvoicePlanner` tests (already-invoiced skipped, period must match frequency), `fees-rules`, `fees-chunk-limit` |
| 4 Parent views invoice | ✔ | parent rules (P4) and My Fees widget tests |
| 5 Payment recorded (staff) | ✔ | payments rule: balance, idempotent id, receipt in same commit; `payment_rules` tests |
| 6 Receipt generated | ✔ | receipts rule + `fee_pdf` (visual output not verified) |
| 7 Balance updated correctly | ✔ | rule enforces `balanceAfter == balance - amount`; `invoice_reconciler` tests |
| 8 "Finance dashboard reflects the transaction" | ✘ | there is no finance dashboard; Fee reports (collections, outstanding by class/section) read the data on demand |

Edge/failure: overpayment refused, reversal ACTIVE -> REVERSED with refund of balance in one commit, waiver <= balance, void with reason, partial payments, reference required for UPI/bank/cheque, tampered amounts denied by rules tests. Parents **cannot** pay online (not implemented), so "parent records payment" does not exist.
**Verdict: PARTIAL** (logic strongly verified; no dashboard; no end-to-end run).

## Workflow C - Attendance
| Step | Covered | Evidence |
|---|---|---|
| 1-2 Teacher signs in and sees assigned classes | ◐ | `teacherAccess` scope enforced by rules and tested; the index is built by a deployed function, not exercised together |
| 3-4 Marks and saves | ✔ | attendance register transaction tests, `attendance-rules` |
| 5 Admin views | ✔ | hub/reports widget tests |
| 6 Parent sees child attendance | ✔ | `parent-attendance-rules`, `my_attendance` tests |

Edge: corrections need a reason and write history; concurrent edits raise "changed by someone else"; finalize; holidays block marking. Parent push on finalize is deployed (`notifyRegisterFinalized`) but untested end to end.
**Verdict: PARTIAL.**

## Workflow D - Homework
Teacher creates -> targets sections/subjects -> publishes -> parent sees -> submission and review. ✔ `homework_write_contract` replayed to rules, `homework-rules`, `homework-storage-rules`, parent homework tests; lateness decided by server time. Notification delivery ◐ (Android push only; not device-tested).
**Verdict: PASS for data flow, PARTIAL for notifications.**

## Workflow E - Examination
| Step | Covered | Evidence |
|---|---|---|
| 1-2 Admin creates exam, schedules subjects | ✔ | `exam_write_contract`, `exam-rules` (a separate exam-timetable screen does not exist) |
| 3-4 Teacher enters marks; validation | ✔ | marks rules (max, absent/exempt), `ResultCalculator` tests |
| Review/approve | ✔ | `sheetUpdateOk` rules |
| 5 Results calculated | ✔ | calculator tests incl. ranks, absent handling |
| 6 Admin publishes | ✔ | finalise -> publish flow, resumable |
| 7 Parent views report card | ◐ | results page ✔; PDF report card has one test file |
Correction after publish: reopen, resultVersion, history ✔.
**Verdict: PASS for data flow, PARTIAL for report card output.**

## Cross-cutting workflow results
- Unauthorized access for every workflow is covered by the sweeps (cross-role and cross-tenant) and passes.
- **No workflow was executed end-to-end in a running app**, which is why none is marked PASS here and why PB-04 is a High finding.
- Defect found while auditing: header regression at phone width (PB-01).
