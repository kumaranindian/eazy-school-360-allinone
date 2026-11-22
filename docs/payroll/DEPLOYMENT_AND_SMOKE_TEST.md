# Payroll: deployment and smoke test

## Deploy order (dev first, prod only with explicit approval)
1. Indexes: `firebase deploy --only firestore:indexes --project <project> --force` (new: collection-group overrides for `payslips.createdBy` and `payslips.updatedBy`, used by account deletion). Wait until they finish building.
2. Functions: `firebase deploy --only functions --force --project <project>` (payroll adds 23 callables; a per-minute quota error is retried by waiting).
3. Web app: `flutter build web --release -t lib/main_<env>.dart --dart-define=APP_ENV=<env>` then `firebase deploy --only hosting`.
4. Rules: `tool/deploy_rules.sh <project>` (no payroll rule is added: pay data has no client rules; the Firestore rules file is unchanged, deploying it is harmless).
Module switch: `payroll` needs `staff`; both are on by default for a school (a school admin of the platform console can switch them per school).

## Smoke test (one school with two staff, a school admin, a finance user, a second school admin, one staff login)
1. Settings: as the school admin open Payroll > Pay components: the built-in Basic salary is there. Add HRA (percentage of Basic, 40%) and Provident fund (deduction, 12% of Basic).
2. Salary: set a structure for both staff (effective the 1st of the month). Revise one: the revision demands a reason; the old version stays in History.
3. Preview: Payroll > Pay for a month: totals match; open a person: lines, days, things to check.
4. Run: as finance start the month: it is CALCULATED; add a one-off bonus and a recovery to one payslip; the totals move; recalculate keeps them.
5. Separation: as finance there is no Approve button. As the school admin who did NOT prepare it, Approve (tick the box if there are things to check). The preparing admin is refused unless "let one administrator prepare and approve" is on.
6. Pay: as finance Mark as paid (mode, reference). The run shows "Recorded as expense EXP-...". Open the expense: Payroll badge, PAID, cannot be edited or cancelled; Expense reports count it under Salaries.
7. Staff: sign in as the staff member with a login: a notice "Your payslip for <month> is available" (no amount), My payslips lists the month, the payslip shows the figures and the one-off item, Download PDF opens a one-page A4 on the letterhead.
8. Privacy: as a teacher WITHOUT a staff record and as a parent: no Payroll or My payslips entry; opening /payroll shows no access. Another school's admin cannot open the URL either.
9. Register: Payroll > register: the month appears with its expense number; Download CSV opens in a spreadsheet (one row per person, a column per component, TOTAL row).
10. Cancel: start a different month, cancel it with a reason; it can be started again.
11. Switch the `payroll` module off in the platform console: every payroll screen and the My payslips entry disappear; switch it on again.
12. Audit: in the platform console search the audit trail for `API_ADJUST_PAYSLIP`: who, which run and person are there; no amount, item name or reason.

## What to check in the logs after deploy
`listMyPayslips`, `getMyPayslip`, `previewPayroll` and the run callables log only the caller's uid and the function name (never a figure). Errors carry a category, not the data.
