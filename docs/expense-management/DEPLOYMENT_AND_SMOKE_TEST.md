# Expense management: deployment and smoke test

Deploy order (dev first, prod only with explicit approval; use `--dry-run` for rules first):

1. `firebase deploy --only firestore:indexes --project <p>` (two composite indexes on `expenses`).
2. `firebase deploy --only functions --force --project <p>` (21 expense callables, `expenseReceiptCleanup`; `--force` because of retry policies; per-minute API quotas may need a wait and a re-run).
3. Web build and hosting (`lib/main_<env>.dart`, `--dart-define=APP_ENV=<env>`).
4. `tool/deploy_rules.sh <p>` last: it releases the BUILT Firestore and Storage rules. The receipts Storage rule (`expenseReceipts`) must be live before anyone uploads a receipt, and the functions before the rule is useful.

No Firestore rules change is needed for expenses: the collections have no client rules (default deny) and are reached only through callables.

## Smoke test (a school with Expenses switched on; people: school admin A, finance F of branch 1, branch admin B of branch 1)

| # | Do | Expect |
|---|---|---|
| 1 | A opens Expenses, then the settings icon | the nine default categories, "Salaries" marked built in; approval switch on |
| 2 | F adds an expense (category, amount 1250.50, today) | a draft `EXP-<year>-00001`, amount shown as 1,250.50 |
| 3 | F attaches a PDF receipt, then a 6 MB file | the PDF appears; the large file is refused before upload |
| 4 | F submits | status Submitted; A has a notice "Expense awaiting approval" (no amount in it) |
| 5 | F tries to approve; B tries to approve | no Approve button for F; none for B until A lists branch admins as approvers |
| 6 | A approves | Approved; F and the finance team get notices |
| 7 | F marks it paid (UPI, a reference) | Paid; the history shows submit, approve, pay with names |
| 8 | A rejects another submitted expense with a short reason, then a proper one | the short one is refused; the proper one rejects; the maker can reopen it |
| 9 | A turns approval off and F submits a new one | goes straight to Approved; the history shows an automatic approval |
| 10 | A opens Reports (this month), switches All branches, exports CSV | totals count approved + paid only; the file opens with amounts as 1250.50 |
| 11 | Switch the Expenses module off for the school in the platform console | the Expenses entry disappears; a direct call is refused |
| 12 | Look at the audit trail as a platform owner | `API_*` events for each step with the request; the export has no rows copied in |
