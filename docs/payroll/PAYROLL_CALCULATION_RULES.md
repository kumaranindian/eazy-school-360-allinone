# Payroll calculation rules (phase P2)

How a month's pay is worked out. The code is `functions/payroll_calculator.js` (pure), `payroll_calendar.js` (school days) and `payroll_preview.js` (reads the facts, no writes). Every rule below has a test in `payroll_calculator.test.js`, `payroll_calendar.test.js` or `payroll_preview.test.js`. In phase P2 nothing is saved: `previewPayroll` shows what a run would pay and why. Runs, payslips and posting come in P3-P5.

## Inputs (all read by the server, never sent by the app)
| Input | Source |
|---|---|
| Salary structure in force on the 1st of the month | `salaryStructures` (latest version effective on or before that date) |
| School days of the month | the branch calendar: `settings/workingDays` (weekly offs, Saturday rules, effective-dated history), `academicYears/*/holidays` (closing holidays, special working days). Same precedence as attendance and leave: a closing holiday wins, then a special working day, then the weekly pattern |
| Attendance | `staffAttendance` for the month: PRESENT, LATE, HALF_DAY, ABSENT |
| Approved leave | `leaveApplications` with `subjectKind` STAFF and status APPROVED; its `countedDateKeys`, session (`halfDay`) and `payType` |
| Employment window | staff `joiningDate`; `statusChangeDate` for RESIGNED / TERMINATED / RETIRED |
| School policy | `payrollSettings/config.unmarkedDays` (PAID default, or UNPAID) |

## The rules
1. Only school days count.
2. Each school day is two halves, each PAID or UNPAID.
   - Approved leave covers its halves: a PAID leave type pays them, an UNPAID type does not (a type with no pay concept pays, with a warning). Leave wins over the attendance mark for the halves it covers.
   - The rest of the day follows attendance: PRESENT and LATE pay; HALF_DAY pays one half; ABSENT does not; a day nobody marked follows the school policy and is ALWAYS reported as something to check.
   - A school day before the joining date or after the leaving date is unpaid.
3. `factor = paid halves / school-day halves`. If nobody is short of a day the structure is paid exactly.
4. Each EARNING is `round-half-up(amount x paid / total)`. A percentage line is recomputed from its prorated basis. A FIXED deduction (an advance recovery) is never prorated. A percentage deduction follows its basis.
5. `net = earnings - deductions`, never negative: if the deductions are more than the earnings, the LAST deductions are reduced until they fit and the shortfall is reported as `unrecoveredDeductionMinor`. Nothing is silently dropped.
6. Late marks and overtime change nothing in v1. A month with no school days pays in full and says so.

## Things the school should know
- Leave and attendance never contradict silently: an approved unpaid leave on a day marked PRESENT stays unpaid and is flagged `LEAVE_AND_PRESENT`; two approved leaves on one day are flagged `LEAVE_OVERLAP` and the first one wins.
- A structure applies to the whole month it is in force on the 1st (changes start on the 1st of a month), so there is no mid-month salary change to apportion.
- Pending or rejected leave never reduces pay. Attendance on a non-school day is ignored.
- Reads are bounded: a branch preview stops with an error above 20,000 attendance records or 5,000 staff leave records for the whole history (the leave read is by kind, not by date; a date-ranged index is a later optimisation).

## Privacy
`previewPayroll` returns pay figures, so it is school admin and finance only (a branch admin, teacher, parent and the staff member themselves get nothing) and its response is not copied into the audit trail (the request, who and which month, is).

# Payroll runs (phase P3)

One run per branch and month: `schools/{s}/branches/{b}/payrollRuns/{yyyy-mm}`, with a `payslips/{staffId}` subcollection (a frozen snapshot per person) and an append-only `history`. Code: `functions/payroll_runs.js`. No client rules: every read and write is a callable for the school admin and finance (a branch admin, teacher, parent and the staff member themselves get nothing yet; own payslips arrive with phase P4).

```
DRAFT -> CALCULATED -> APPROVED -> PAID        (CANCELLED from DRAFT, CALCULATED or APPROVED)
```

| Step | Who | Rule |
|---|---|---|
| Create (and calculate) | school admin, finance | one run per branch and month; the month cannot be in the future or more than 2 years back; a CANCELLED month can be started again (the history is kept and continues). The payslips are computed by the same code as the preview, so a run pays exactly what the preview showed |
| Recalculate | school admin, finance | only while DRAFT or CALCULATED; keeps one-off items already entered; people who no longer qualify are removed; an item the new base cannot carry (the net would go negative) is dropped and counted in the answer |
| Adjust (add or remove a one-off item) | school admin, finance | only while CALCULATED; a name (2-60), an amount, a reason (10-300); at most 10 per payslip; the net may never go below 0; the history names the item and the reason, never the amount |
| Approve | school admin only | the person who prepared it (created, recalculated or adjusted) cannot approve, unless the school switched `allowSelfApproval` on (one-administrator schools); a run with things to check or staff without a structure needs an explicit acknowledgement; the stored totals must equal the sum of the payslips (otherwise recalculate); the version the approver saw must still be current |
| Pay | school admin, finance | mode (cash, bank transfer, UPI, cheque, card, other), optional reference, a date that is not in the future and not before the month; paying twice is harmless; a paid run is final |
| Cancel | finance before approval, school admin at any open stage | a reason of 10-300 characters; a paid run cannot be cancelled |

After APPROVED nothing in the run changes (a correction is a one-off item in the NEXT run). Every change runs in a transaction that re-reads the run, checks the status it came from and writes the new status and a history entry together. Responses of the writes carry no amounts; the reads that do (`listPayrollRuns`, `getPayrollRun`, `getPayslip`) are kept out of the audit trail, and the request of `adjustPayslip` is recorded with the amount masked.

Not yet: publishing payslips to staff and notifications (P4), posting the paid run to the Salaries expense and the payroll register (P5).

# Payslips (phase P4)

**Published means paid.** Marking a run PAID publishes its payslips (`publishedAt` on the run). Nothing is readable by a staff member before that: a calculated, approved or cancelled run answers NOT_FOUND (it does not even hint that a run exists).

**A staff member reads only their own.** `listMyPayslips` and `getMyPayslip` (`functions/payroll_payslips.js`) take no staff id: the staff record is found from the signed-in user (`staff.userId`), in the user's own branch(es) (a school admin is looked up in every branch). Refused: a parent, a user of another school, a deactivated user, a platform admin, a school with the `payroll` module off or suspended; a user with no staff record gets an empty list or NOT_FOUND. The answer has the school and branch names, the days, every line (with the structure amount when attendance reduced it), the one-off items by name and amount (not the internal reason an administrator wrote), totals, the paid date and the payment mode (not the reference). It never contains the warnings that approvers saw. Responses are kept out of the audit trail.

**Notification.** Paying creates one in-app notice per staff member with an ACTIVE login of this school (`PAYSLIP_PUBLISHED__{period}__{uid}`, written with `create`, so a repeat creates nothing and a retried payment completes any that were missed). The text is "Your payslip for November 2026 is available." and never contains an amount (it shows on a lock screen). The existing push trigger delivers it; tapping it opens My payslips.

**PDF.** Built on the device from the answer (`PayslipPdf`: one A4 page on the school letterhead, the same `FeeLetterhead` and money text as invoices and receipts; many lines continue onto further pages), so no pay data is generated or stored on a server. A staff member prints or saves their own from My payslips; a school admin or finance user can print a copy of any payslip of a PAID run from the run page (for staff without a login).

Not yet: posting the paid run to the Salaries expense and the payroll register with CSV (P5).

# Expense posting and the register (phase P5)

**One expense per paid run, in the same transaction as the payment.** Marking a run PAID also creates ONE expense in the Salaries category (`source: PAYROLL`, id `payroll_{yyyy-mm}`, number from the branch's normal `EXP-yyyy-NNNNN` sequence, status PAID, expense date = the paid date, payee "Payroll November 2026", the payment mode and reference of the run). The amount is the NET pay paid out (earnings less deductions, one-off items included); statutory remittances of the deductions are a separate payment and are not recorded by payroll. Because the posting is in the payment's own transaction, a paid run always has its expense and never two, and a repeated payment posts nothing more. A run whose net pay is 0 posts no expense. The expense is already PAID, so it can be neither edited nor cancelled in the expense module (the existing rules); the expense detail shows a Payroll badge with a link to the run, and the run shows "Recorded as expense EXP-...". The existing expense reports count it automatically under Salaries (approved + paid), so there is no double entry. The expense is posted even when the school has the `expenses` module switched off (it is a financial record; it becomes visible when the module is switched on).

**The register** (`functions/payroll_register.js`): `getPayrollRegister` lists the PAID runs of a branch (or, for a school admin, the whole school) between two months (at most 24), newest first, with totals, how each was paid and its expense number; calculated, approved and cancelled runs are not a record of payment. `exportPayrollRegister` returns the CSV of one PAID run: one row per person, one column per pay component (earnings first), the one-off items summed, totals, plain decimals in the currency's own precision, spreadsheet-formula-safe (a name that starts with `=`, `+`, `-` or `@` is neutralised). School admin (any branch) and finance (own branch) only; responses are kept out of the audit trail.
