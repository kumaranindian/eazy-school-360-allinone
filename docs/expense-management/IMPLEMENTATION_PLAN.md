# Expense Management and Staff Payroll: implementation plan

Status: expenses E1-E5 and hardening are built, deployed (dev and prod) and merged into `develop`; payroll P1 is built on branch `feature/payroll` (2026-11-17), P2-P5 are next. Decisions taken: approval is a per-school setting; roles are School Admin (the school owner is a School Admin), Branch Admin (own branch) and Finance; budgets later; staff payroll is in scope; recurring and reimbursable expenses are out of v1.

Follows the repo's conventions: feature-first (`lib/features/<f>/{domain,data,presentation}`), pure rules in domain, money as integer minor units (`Money` with the currency), school days via `SchoolTime`, branch scoping, write paths as callables, audit through `call_audit.js`, one phase at a time with tests and docs.

## 1. Scope

| In v1 | Later |
|---|---|
| Expense entry with category, amount, date, payee, payment mode, reference, receipt | Budgets and budget vs actual |
| Optional approval (per school), with reasons and history | Recurring expenses |
| Mark paid, cancel, list and filter, reports by category / month / branch, CSV | Reimbursements, vendor management |
| Staff payroll: salary structure, monthly run, payslips, payment, register | Statutory filings (PF/ESI/TDS returns), bank file export |

## 2. Roles and permissions

| Action | School Admin | Branch Admin | Finance | Everyone else |
|---|---|---|---|---|
| Create / edit own draft expense | yes | own branch | yes | no |
| Approve / reject | yes | own branch (if allowed by setting) | no (default) | no |
| Mark paid, cancel | yes | no | yes | no |
| Categories, expense settings | yes | no | no | no |
| Expense reports | yes | own branch | yes | no |
| Salary structures, payroll runs | yes | no | prepare only | no |
| Approve / pay payroll | yes | no | pay only | no |
| Own payslip (read) | | | | the staff member |

Assumption to confirm: nobody can approve their own expense or payroll run (separation of duties), unless the school has a single admin, in which case the setting `allowSelfApproval` applies.

## 3. Expense flow

`DRAFT -> SUBMITTED -> APPROVED | REJECTED -> PAID`, `CANCELLED` from DRAFT/SUBMITTED/APPROVED.
When the school setting `approvalRequired` is **off**, submit goes straight to APPROVED and the approver step is skipped (still recorded in history). All transitions live in one table in `expenses.js` (like `TRANSITIONS` in the school lifecycle), each with the allowed roles, a required reason where it matters (reject, cancel) and an idempotency key.

1. Draft: fields editable, receipt optional.
2. Submit: validated (amount > 0, category active, date not in the future by the school's zone, currency matches the school's).
3. Decide: approver approves or rejects with a reason (>= 10 chars on reject).
4. Pay: payment mode (cash, bank, UPI, cheque), reference, paid date; becomes read-only.
5. Cancel: before payment only.

## 4. Data model (all new; no client write rules)

- `schools/{s}/branches/{b}/expenses/{id}`: `number` (server counter, `EXP-2026-0001`), `categoryId`, `categoryNameSnapshot`, `amountMinor`, `currency`, `expenseDate`, `payee`, `description`, `paymentMode`, `paymentReference`, `status`, `receipt` metadata (Storage path, type, size; never a URL), `submittedBy/At`, `decidedBy/At/reason`, `paidBy/At`, `source` (`MANUAL` | `PAYROLL`), `createdBy/updatedBy`, `schoolId`, `branchId`.
- `.../expenses/{id}/history/{n}`: from, to, actor, reason, at.
- `schools/{s}/expenseCategories/{id}`: name, active, `system` flag (Salaries is system, not deletable); defaults seeded for new schools.
- `schools/{s}/expenseSettings/config`: `approvalRequired`, `allowSelfApproval`, `approverRoles`, receipt required over an amount (optional).
- Payroll: see section 6.

Clients read through callables or narrowly scoped read rules; writes only through callables. If the Firestore rules size budget is tight (it sits at the release limit), reads also go through callables.

## 5. Cross-cutting checklist (each item has a test)

| Area | Work |
|---|---|
| Permissions | `Permission.expensesView/Create/Approve/Pay/Manage`, `payrollView/Prepare/Approve/Pay`, `payslipViewOwn` in `lib/core/permissions`; mirror in rules and callables; allowed and denied cases in `firestore-tests/` |
| Module switch | `expenses` and `payroll` added to the feature catalogue (Dart and `functions/features.js`), with `payroll` depending on `staff`; enforcement in callables via `feature_guard` |
| Storage | receipt path `schools/{s}/branches/{b}/expenses/{id}/receipt/...`, type/size/signature limits in `storage.rules` and the pure policy class, create-only |
| Audit | callables are covered by `call_audit`; add `expenses`, `payrollRuns`, `payslips` to `audit.MODULES`; payroll responses are large and sensitive, so decide (section 8) whether to omit response bodies |
| Account deletion | entries for every new collection in the deletion processor and `docs/account-deletion-data-matrix.md` (financial records are kept, never deleted; `deletion_coverage.test.js` fails otherwise) |
| Currency lock | the first expense or payslip sets `currencyLocked` |
| Notifications | to approvers on submit; to the submitter on decision; to staff when a payslip is published |
| Multi-branch | branch admins act in their branch; school admin/finance can pick the branch (`ActingBranchBanner`) |
| Help and docs | feature doc, role matrix, help page entry |

## 6. Staff payroll

Payroll is a separate module that depends on Staff (and uses Staff Attendance and Leave).

**Concepts**
- **Pay components** (`schools/{s}/payComponents`): earnings (basic, HRA, allowance) and deductions (advance recovery, tax, PF, ESI), each a fixed amount or a percentage of another component. No statutory rule is hard-coded: the school configures its own, because the product is multi-country.
- **Salary structure** per staff member (`staff/{id}/salary`, effective-dated): component values, with history so past payslips never change.
- **Payroll run** (`payrollRuns/{yyyyMM-branch}`): one per branch and month. States `DRAFT -> CALCULATED -> APPROVED -> PAID` (and `CANCELLED` before payment), same transition-table pattern.
- **Payslip** (`payrollRuns/{run}/payslips/{staffId}`): a frozen snapshot of earnings, deductions, days worked, unpaid-leave days, net pay in minor units.

**Calculation (pure, unit-tested `PayrollCalculator`)**
- Days in month and working days from the school calendar and holidays (existing holidays and staff attendance days).
- Unpaid leave and absences reduce pay pro rata; paid leave does not.
- Rounding rule fixed and documented (round half up per component, net = earnings - deductions, never negative).
- A run is recomputable while in CALCULATED; after APPROVED it is frozen. Corrections are made as adjustments in the next run, not edits.

**Flow**
1. Finance (or admin) creates the run for the month and branch; the server calculates all payslips.
2. Review: adjust per-employee one-off items (bonus, deduction) with reasons.
3. Admin approves (not the same person who prepared it, unless `allowSelfApproval`).
4. Mark paid with the payment mode and date; payslips are published to staff.
5. On payment, one expense per run is posted to the system category **Salaries** (`source: PAYROLL`), so expense reports include payroll without double entry.

**Privacy**: salary data is the most sensitive data in the system. Only School Admin, and Finance (prepare/pay), can read structures and runs; a staff member reads only their own published payslip; Branch Admin gets totals, not individual pay (to confirm). Never in logs or push text; payslip PDF generated on demand with the school letterhead (reuse the A5 letterhead work).

## 7. App

- `lib/features/expenses/`: `Expense`, `ExpenseCategory`, `ExpenseSettings`, `ExpenseRules` (pure state machine and validation), `ExpenseRepository` (interface) + `FirebaseExpenseRepository`; pages: list (FilterBar, StatChipsBar by status), form (with receipt upload), detail (timeline), categories, settings, reports.
- `lib/features/payroll/`: pay components, salary structure editor on the staff profile, run list and run detail (table of payslips with adjustments), payslip view and PDF, staff "My payslips" page.
- Routes `expenses_routes.dart`, `payroll_routes.dart`; dashboard tiles gated by role and module switch; `FakeExpenseRepository` etc. in `test/support`.
- Layout tests at phone/tablet/desktop and larger text scale for every new page.

## 8. Decisions still open (defaults in bold)

1. Branch Admin approval of own-branch expenses: **yes only if the school's approver roles include them**.
2. Payslip numbers shown to Branch Admin: **totals only**.
3. Should audit store payroll response bodies? **No: store the request keys and result, mask amounts per employee**, because the audit trail is broadly readable by platform owner/compliance. (The generic `call_audit` stores full responses; payroll callables need an entry in its response-omitted list.)
4. Payroll posting to expenses at payment: **one expense per run**.
5. Statutory components: **configurable only, no built-in PF/ESI/TDS rules**.
6. Pay frequency: **monthly only in v1**.

## 9. Phases (one at a time; tests, status and coverage docs updated each time)

| # | Phase | Output |
|---|---|---|
| E1 | Foundation | models, categories (seeded), settings, permissions, module switches, deletion matrix, rules and tests |
| E2 | Expenses create / list | callables, repository, list and form pages |
| E3 | Receipts | upload / view / remove with Storage rules |
| E4 | Approval and payment | transition table, history, notifications, per-school approval setting |
| E5 | Reports and export | by category / month / branch, CSV, dashboard tile |
| P1 | Payroll foundation | pay components, salary structures with history, privacy rules |
| P2 | Calculator | `PayrollCalculator` with attendance and leave, exhaustive unit tests |
| P3 | Runs | create, calculate, adjust, approve, pay, freeze |
| P4 | Payslips | staff view, PDF, publishing, notifications |
| P5 | Expense posting and reports | Salaries expense per run, payroll register, CSV |
| H | Hardening | security tests, audit coverage, role-by-callable proof, docs, dev deploy and smoke test, then prod |

Each phase ends with: Dart and Node tests green, rules tests green (source and built artifact), `flutter analyze` and `dart format` clean, `AUDIT_EVENT_COVERAGE.md` and `IMPLEMENTATION_STATUS.md` updated. Production deployment only with your explicit approval.
