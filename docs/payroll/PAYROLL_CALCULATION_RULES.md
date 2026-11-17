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
