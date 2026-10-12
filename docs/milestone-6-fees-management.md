# Milestone 6 — Fees Management, Invoices, Payments & Receipts

Status: implemented and verified as far as this environment allows (see §12 for what was **not** verified).

## 1. Scope
Fee structures, student fee assignment (single + bulk with preview), invoices (bulk generation with preview, search/filter, void, print/PDF), payments (full/partial/multiple, idempotent), reversal/refund records, waivers, receipts (view/print/PDF), dashboards/reports, parent read-only views. **No payment gateway, payroll, leave, timetable, exams, transport or inventory.**

## 2. Money rules
| Rule | Definition |
|---|---|
| Storage | Integer **minor units** (paise). No doubles anywhere. |
| Concession | `FIXED` (minor units) or `PERCENT` in **basis points**; discount = `(amount*bp + 5000) ~/ 10000` (round **half up**), capped at the line amount. Per line: `discount + net == amount`. |
| Invoice | `payable = subtotal − discount`; `balance = payable − waived − paid`. |
| Status | `PAID` if balance ≤ 0; `PARTIALLY_PAID` if paid+waived > 0; else `ISSUED`; `VOID` terminal (only when paid == 0). **Overdue is derived** from due date, never stored. |
| Overpayment | Rejected: `0 < amount ≤ balance` (UI, repository transaction, and security rules). |
| Waiver | Admin only, `0 < amount ≤ balance`, reason required, separate `invoiceWaivers` record. |
| Reversal / refund | Never an edit: a `paymentReversals/{paymentId}` record is written, payment + receipt are marked `REVERSED`, invoice paid/balance/status are restored. A payment can be reversed once. Receipts are retained. |
| Void | Admin only, reason required, only when nothing is paid. Releases the line locks so the period can be re-billed. History is kept. |
| Historical invoices | Frozen snapshot (names, lines, amounts, school/branch names). Editing a fee structure or a concession never changes an issued invoice. |

## 3. Identifiers and uniqueness
- Fee structure `{yearId}__{codeLower}`; assignment `{studentId}__{structureId}`; invoice `{studentId}__{yearId}__{periodKey}`; payment id = **idempotency key** (`pay_…`, generated once per dialog, reused on retry); receipt and reversal reuse the payment id.
- Period keys: `M-2026-06`, `Q-2026-2`, `H-2026-1`, `A-2026`, `O-slug`, `C-slug`. One-time fees use charge key `ONCE`.
- `feeCharges/{assignmentId__chargeKey}` lock per billed line → a line can never be billed twice; deleted on void.

## 4. Numbering (concurrency-safe, no backend)
`INV-{startYear}-{000001…}`, `RCT-…`. A counter doc (`feeCounters/{kind}_{yearId}`) is read and bumped **inside a Firestore transaction**; a unique reservation doc (`invoiceNumbers/{n}`, `receiptNumbers/{n}`) is created in the same commit. Rules require the reservation sequence to satisfy `counterBefore < seq ≤ counterAfter`, and the `!exists` create rule makes a duplicate number impossible. Numbers are unique and increasing; **gaps are possible** (aborted/voided). Not an unsafe "query max, then +1".

## 5. Lifecycle
Assign → (preview) → generate invoices (preview, then chunks of 8 in transactions; existing invoices skipped ⇒ idempotent) → collect payments (one transaction each) → optionally waive / reverse / refund / void. Ineligible students (not enrolled: transferred, withdrawn, etc.) are never assigned or billed; the preview lists each skip with the reason.

## 6. Roles (existing RBAC extended)
| Capability | Platform/School/Branch admin | Finance | Teacher | Parent |
|---|---|---|---|---|
| Fee structures, concessions, waivers, void, reversal | ✅ | ❌ | ❌ | ❌ |
| Assign, generate, collect, read, reports | ✅ | ✅ | ❌ | ❌ |
| Own children's invoices/payments/receipts (read) | – | – | ❌ | ✅ (ACTIVE, portal-enabled links only) |

New permissions: `viewFees, manageFeeStructures, assignFees, issueInvoices, collectPayments, grantConcessions, voidInvoices, reversePayments, viewFeeReports, viewOwnChildFees`.

## 7. Security rules
Every fee collection is tenant (`schoolId`) and branch scoped. Invoice updates are only valid as one of four events (`PAYMENT`, `REVERSAL`, `WAIVER`, `VOID`), each tied via `existsAfter/getAfter` to its record, with arithmetic and status recomputed in the rule. Rules evaluate at commit, so two concurrent stale payments cannot both pass the `amount ≤ balance` check. Payments, receipts, reversals, waivers and audit logs cannot be deleted. Parent reads use `canAccessAsParent` (child ↔ active portal parent link).

### Trust limitation (read this)
A client transaction does **not** protect against a *malicious* client with valid credentials; Firestore rules are the real guard, and they cannot do everything. Known unenforceable-in-rules item: **rules cannot sum the invoice `lines` list**, so a finance user could issue an invoice whose line items do not add up to the stated `subtotal` (the headline arithmetic *is* enforced). If that threat matters, issue invoices from a Cloud Function / trusted backend that recomputes from the fee structures. Same applies to confirming that a line's amount equals the structure amount.

## 8. Reports and aggregation
`AggregateQuery` `sum()`/`count()` over `invoices`/`payments` (no document downloads). Void invoices and reversed payments are excluded by query. The hub flags totals that do not balance. Consistency: aggregates are point-in-time reads of separate queries, so a payment landing between them can briefly show a mismatch; refresh resolves it.

## 9. Indexes
15 added to `firestore.indexes.json` (30 total): invoices by year/status/class/section/student × due date; payments by year/status/method/student × date; receipts by student; reversals by year/kind/date. The emulator does not enforce indexes — **they were not exercised**; deploy and watch for "index required" errors on first use.

## 10. Screens
Hub, structures (+form), assignment (+bulk preview), invoices (list, ledger header per student), bulk generation (+preview/confirm), invoice detail (+actions), collect-payment dialog, payments history, receipt (print/PDF), reports, parent "My Fees" (+invoice, receipt). PDFs print amounts as `INR 1,500.00` (the bundled PDF font lacks ₹).

## 11. Tests
- Dart unit: money, config, invoice/payment arithmetic, planners — `test/fees/` (94).
- Widget: `test/widget/fees_ui_test.dart` (61) — routing/nav matrix, hub, forms, collect (validation, double-tap = one request, stable idempotency key on retry), reversal/waiver/void reasons, bulk preview/confirm, parent view, responsive widths.
- Rules: `firestore-tests/fees-rules.test.mjs` (36) — tenant/branch/teacher/parent isolation, direct unauthorized reads & writes, overpayment, concurrency, idempotency, replay, reversal, void, numbering, audit.
- Full: 465 Flutter tests, 134 rules tests.

## 12. Known issues / not verified
1. No end-to-end run against a real Firebase project.
2. Dart repositories are not tested against the emulator (only the rules and pure logic are); a rules-vs-Dart shape mismatch would surface at runtime.
3. Invoice line sums not verifiable in rules (§7).
4. One payment applies to one invoice; no allocation across invoices; no draft invoices; fixed payment-method set.
5. Indexes unexercised (§9). iOS cannot build here (iOS 26.5 platform missing).
6. During Milestone 4, `dart format` was run across all of `lib/` and `test/`, reformatting some pre-existing files (disclosed then; not reversible).

## 13. Deploy
`firebase deploy --only firestore:rules,firestore:indexes` (wait for indexes to build), then create a finance user and fee structures for the active year. Run rules tests with project id `demo-eazy-school-360` (Storage rules need it).
