# Race-condition & data-integrity audit

Only interactions where a concrete unsafe interleaving exists are listed. IDs refer to BUG_REGISTER.md. "L" = lead-verified, "S" = sub-audit report.

## A. Confirmed unsafe interactions

| ID | Competing operations | Interleaving | Wrong final state | Fix & regression test |
|---|---|---|---|---|
| ACAD-2 (L) | Admit/import/transfer student ×2 with the same admission number | both `isAdmissionNumberAvailable` queries return "free" before either commit (`firebase_student_repository.dart:311-370`); ids are random so nothing collides; no rule on `admissionNumber` | two students share an admission number (case variants also pass) | create-only reservation doc `admissionNumbers/{lower}` in the same batch + `existsAfter` rule (as `staffCodes`). Rules test: two creates → one allow, one deny; case variant denied |
| ACAD-3 (S) | Marks save (5-entry chunks) vs. a failing chunk | chunks 1-2 commit, chunk 3 fails; UI keeps old `revision`; retry sends `revision+1` of the stale value → rules reject every retry | partial sheet saved; user stuck until reload | on any failure reload & rebase; report written count. Test: fake repo failing 2nd chunk then succeeding |
| ACAD-4 (S) | Two admins approve different sheets of one exam | both `get()` `approvedSheets=N`; first commits N+1; second batch asserts N+1 (rule `examApprovedMovesBy`) and is denied | no corruption (rules hold) but approval fails nondeterministically with a generic error | `runTransaction`/`FieldValue.increment`. Test: parallel approvals both succeed, counter = 2 |
| ACAD-7 (S) | Two concurrent in-branch transfers of one student | both query ACTIVE records, both batch-close it and create a new ACTIVE one | two ACTIVE records; `currentSectionId` last-writer-wins; student appears in two rosters | transaction with expected-record precondition and deterministic record id. Test: two parallel transfers → one `ValidationFailure` |
| STATE-1 (L) | Students/Parents list: Load-more ×2, or slow search then fast search | `_loadPage` has no request id and never sets `_isLoading` on load-more; the late response of the older query overwrites `_items/_cursor` | duplicated rows, rows of a previous query under a new filter, endless spinner on error | use `PagedListController` (generation counter). Test with out-of-order fake futures |
| STATE-2 (S) | Leave-balance search, link-parent dialog, admission parent search | no token; `finally` of the first response clears `_searching` | stale results | token + try/catch/finally |
| NOTIF-1 (L) | Sign-out (any path but the app-bar button) vs. next login on same device | device doc of user A is never deleted; user B logs in | A's pushes delivered to B's device | central unregister before every `signOut` + `lastSeenAt` expiry |
| NOTIF-3 (S) | Delivery claim vs. transient failure | claim FAILED/PROCESSING-stuck; no retry flag, no sweeper | notice permanently lost | `retry:true` + re-runnable claims or sweeper |
| NOTIF-5 (S) | Two redeliveries taking over a stale claim | read then unconditional `update` (`delivery_log.js`) | double send to everyone (collapse tags mask most) | transactional takeover on `startedAt` |
| STATE-4 (S) | "Mark all read" vs. single mark / two devices | `addReadIds` = read-merge-set (`firebase_notification_repository.dart:183-199`) | lost update, item reappears unread | `FieldValue.arrayUnion` |
| STATE-6 (S) | `switchBranch` (await `getBranch`) vs. sign-out / account switch | assigns `state` from a stale `current` after the await | previous user's tenant overwrites new state (splash stuck) | capture uid before await, compare after. *Introduced this session.* |

## B. Potential / not reproduced
* ACAD-8 — finalise can freeze marks that changed after the on-screen calculation (exam `revision` is not bumped by sheet moves).
* ACAD-9/10 — attendance and leave rely on client-built keys that rules cannot verify (cross-section attendance record that blocks the real teacher; leave day-locks not required by the create rule). Sound under honest clients, forgeable by a crafted one.
* ACAD-13 — holiday duplicate by double tap (random id + query-then-write); working-day history computed client-side.
* ACAD-15 — `changeStaffStatus` ends assignments in chunks before the status doc.
* PERF-2 — `parentAccess` refresh: read links then `set`; an unlink in between leaves a stale grant until the next refresh.
* `registerDevice`: set → query → delete is not transactional; two accounts registering one token can each delete the other's doc (fail-safe: nobody receives).
* Firestore on-device persistence is not cleared on sign-out (STATE-7) — UNKNOWN on real shared devices.

## C. Verified correct (so the register is balanced)
* **Payment collection** is one transaction: re-reads the invoice, validates against the *current* balance, takes the next receipt number from the counter, writes payment + receipt + number reservation + counter + invoice together; the payment id is the idempotency key and a replay with different content is refused (`firebase_payment_repository.dart:36-215`). Rules independently require the invoice change to equal the payment. Two cashiers racing are serialised; the loser re-runs against the new balance. UI creates the key once per dialog and guards `_busy` (`fee_action_dialogs.dart`).
* **Reversal** is one transaction that re-reads payment and invoice, writes the reversal record, flips payment + receipt, restores the invoice and writes the audit entry in the same commit.
* **Invoice generation** is chunked (6 invoices per transaction), idempotent by invoice id, numbering from a counter read/written in the same transaction; money is integer minor units.
* **Attendance register save** is a transaction comparing day revision and every entry revision, with one immutable history doc per revision.
* **Leave decisions/cancellations** re-read inside transactions; ledger ids `…__consume/__restore` make double consumption impossible; per-day lock docs serialise submissions.
* **Homework** lateness decided by `request.time` in the rules; **timetable publish** guarded by a publish-sequence lock; **substitutions** bump a per-date `seq`.
* **Push delivery claim** is an atomic `create()` keyed on the event id; event notices use deterministic ids.

## D. Residual financial-integrity limits (design, not bugs)
Client-supplied business dates (`paymentDateKey`, `issueDateKey`, `reversalDateKey`) come from the device clock and rules only check format (a back-dated receipt is possible for a user who may collect); a legitimate cashier can record a payment that never happened (process control: separate cashier/approver, daily reconciliation with `InvoiceReconciler`); the per-year counter serialises billing (OPS-4); no online-payment signature verification exists because no gateway exists. Move to a callable-function backend before any gateway.
