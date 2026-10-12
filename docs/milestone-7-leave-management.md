# Milestone 7 — Student & Staff Leave Management

Status: implemented and verified as far as this environment allows. See §14 for what was **not** verified and the design limits.

## 1. What was assessed first (source is the truth)
| Area | Finding | How M7 uses it |
|---|---|---|
| Attendance model | `AttendanceStatus` is PRESENT/ABSENT/LATE/HALF_DAY. M5 deliberately left leave out ("a future Leave module will reference attendance days rather than write contradictory LEAVE records"). | Leave is a **separate record** shown as an annotation. Attendance documents are never written by leave. |
| Calendar | M2 working days + holidays + special working days, resolved by `AttendanceCalendar`. | The same function counts leave days (`LeaveDayCalculator`). |
| Parent ↔ student | `parentLinks` (ACTIVE, `canAccessPortal`) and `canAccessAsParent` in rules. | Parent reads/writes are gated by it. |
| Staff ↔ login | `staff.userId`. | Staff self-service resolves "my staff record" through it (`isOwnLeaveStaff`). |
| Roles | admins, TEACHER, FINANCE, PARENT. **No approver/principal role.** | Reviewers are `canManageStaff` (school/branch/platform admins). A "designated approver" is not represented (§14). |
| Notifications | None existed. | Added an in-app collection only. No email/SMS/WhatsApp. |
| M6 fees | Untouched. | No fee logic changed. |

## 2. Features
Leave types (student + staff, configurable policy) · student leave by parent (and by office staff on behalf, when the branch allows) · staff self-service leave · approval workflow (approve / reject / return for correction / withdraw / cancel approved) · append-only decision history · staff balances with a ledger, adjustments and carry-forward · overlap prevention that holds under concurrency · supporting documents · leave calendar · reports (aggregate queries) · in-app notifications · attendance annotations.

## 3. Data model (all under `schools/{s}/branches/{b}/`)
| Collection | Id | Purpose | Written by |
|---|---|---|---|
| `leaveTypes` | `{KIND}__{code lower}` | Policy: pay type, document/reason required, half days, max days, roles, employment types, entitlement, accrual, carry-forward, over-balance policy, status. Never deleted. | admins |
| `leaveApplications` | `lv_…` (client-generated, reused on retry) | **Private** record: subject, applicant, type snapshot, dates, units, counted dates, reason, attachments, status, revision, decision. | applicant; reviewers (decision fields) |
| `leaveHistory` | `{applicationId}__{revision}` | Append-only: from/to status, event, actor, remarks, time. | with every change |
| `leaveCalendar` | = applicationId | **Minimal public face** of an approved leave: who, dates, session. No reason/type/document. | reviewers, with approval/cancellation |
| `leaveDayLocks` | `{KIND}_{subject}__{date}__{FIRST|SECOND}` | One doc per subject per date per session: DB-level overlap guard. | applicant; released with the application |
| `leaveBalances` | `{staff}__{typeId}__{year}` | Movements only: entitlement snapshot, carry-forward, adjustments, consumed. | admins, only with a ledger entry |
| `leaveLedger` | `{app}__consume`, `{app}__restore`, `adj_…`, `{balance}__carry` | Append-only balance movements. | admins |
| `leaveSettings/policy` | `policy` | `allowAdminOnBehalf` (default off). | admins |
| `notifications` | `{app}__{EVENT}__{rev}__{recipient|REVIEWERS}` | In-app notices. | with the event |

**Units.** Leave is counted in half-day integers (2 = one day); no double anywhere. **Dates** are civil `yyyy-MM-dd` keys plus a UTC-midnight `Timestamp` (same convention as attendance), so a date cannot shift with timezone. **Leave year = academic year**; an application must fall inside one.

## 4. Status transitions
```
          submit                approve                     cancel (reviewer only)
(none) ───────────► PENDING ───────────────► APPROVED ─────────────────────► CANCELLED
                      │  ▲                      
        reject        │  │ resubmit (applicant)
   REJECTED ◄─────────┤  │
        return        ▼  │         withdraw (applicant): PENDING | RETURNED ► WITHDRAWN
                   RETURNED
```
Only PENDING and APPROVED hold days (locks + calendar entry). REJECTED, RETURNED, WITHDRAWN, CANCELLED release them. A reviewer **cannot decide their own application** (applicant uid, or the staff member's own login). Approved leave is cancelled only by a reviewer, with a reason; the applicant withdraws only open applications.

## 5. Leave-day calculation (one implementation)
`LeaveDayCalculator.compute`: a date counts if the **branch calendar** says it is a school day (holidays excluded, special working days included, weekly pattern from settings — nothing hard-coded), or every day for types with `countNonWorkingDays`. Half day = 1 unit, only on a single date, only if the type allows. Rejected: end before start, outside the academic year, longer than the type's maximum (global cap 60 days), a range with no school day. Everything — forms, portals, planner, reports — uses it.

## 6. Balance model
```
available = accrued(entitlement, accrual, today) + carry-forward + adjustments − consumed
```
- Accrual: `UPFRONT` (all of it) or `MONTHLY` (⌊entitlement × months-started / 12⌋ in half-day units, never above the entitlement).
- **Pending days are not reserved.** They are shown ("if approved there may not be enough") but only consumed on approval, which re-checks the balance in the transaction. Rejected/withdrawn/returned never touch the balance.
- Approval of tracked leave: ledger `CONSUME` (`{app}__consume`) + balance update in the same transaction. Cancellation: ledger `RESTORE` (`{app}__restore`, only if a consume exists). Ids are derived from the application, so a retry cannot deduct or restore twice.
- Over-balance policy per type: `BLOCK` (refused) or `WARN` (allowed, the reviewer sees it).
- Adjustments: admin only, non-zero, with a reason, one ledger entry per dialog (`requestId`), cannot make the balance negative in the UI.
- Carry-forward: `min(closing available, type limit)`, creates next year's balance with a `CARRY_FORWARD` entry; the rules cap it at the type's limit.
- Unpaid and untracked types have no balance.
- A type's later edits do not rewrite a year in progress: the entitlement/accrual are **snapshotted** into the balance at creation.

## 7. Attendance integration
Chosen approach: **a dedicated approved-leave reference** (`leaveCalendar`), displayed as an annotation on the M5 registers (student and staff).
- Attendance records, statuses, remarks, finalization and correction rules are untouched; leave never marks, changes or finalizes anything.
- Approval after attendance was marked: the annotation appears; the saved status stays. Finalized registers keep their status; correcting still needs the existing manager + reason workflow.
- Cancellation: the calendar entry becomes CANCELLED and the annotation disappears; nothing else to undo (there was no attendance effect).
- Idempotent: the calendar entry id is the application id (one per application); the annotation map is keyed by subject, so repeats collapse.
- Half days show the session. Holidays/non-working days are not in `countedDateKeys`, so are never annotated.
- Lookup failure never blocks marking attendance (tested).
- Staff-leave annotations are readable by reviewers only (rules); finance/teachers viewing the staff register simply see none.

## 8. Notifications
In-app only (`notifications`). A notice is written **in the same commit as the event** it announces (transaction/batch), so one exists exactly when its event happened; a retried event fails its precondition and writes nothing — no duplicates. Recipients: the applicant for decisions/returns/cancellations/balance adjustments; the reviewers' feed for submissions/withdrawals. Rules tie type to the event (`SUBMIT→LEAVE_SUBMITTED`…), the writer to a party of the event, and the recipient to the applicant. Bodies carry name and dates, never the reason. The reviewers' feed has no per-user read state. **Nothing is sent outside the app, and the app never claims delivery beyond "readable in the app".** If push/e-mail is added later, `LeaveWrites.notification` is the single place.

## 9. Security
Rules (`firestore.rules`, "Leave (Milestone 7)"):
- Tenant/branch isolation on every collection; reviewers are `canManageStaff`.
- **Applications are private**: the applicant, a parent with an ACTIVE portal link, the staff member themself, reviewers. Teachers/finance/other parents cannot read them.
- **Create**: `applicantUserId == uid`; student ⇒ `canAccessAsParent` (or reviewer with `allowAdminOnBehalf`); staff ⇒ own staff record. Type exists, active, matches kind, snapshot name/pay type true; units = 2×counted dates (half day = 1, single date, type allows); reason/document per type; ≤ 3 attachments; year-ceiling balance check for tracked BLOCK types.
- **Update** is one of: withdraw (applicant, PENDING/RETURNED), resubmit (applicant, RETURNED, body re-validated), decide (reviewer ≠ applicant ≠ staff subject; remarks for reject/return; calendar entry and, for tracked leave, ledger + balance move in the same commit), cancel approved (reviewer; calendar CANCELLED; restore ledger + balance in the same commit). Every change requires its matching `leaveHistory` entry (`existsAfter`/`getAfter`). Rules evaluate at commit, so two concurrent decisions cannot both pass the "from PENDING" check.
- Locks: creation tied to an application of the caller; deletion only once the application no longer holds days.
- Balances/ledger: only reviewers, only together (`lastLedgerId` ↔ ledger entry, units equal, replay refused); staff read their own.
- Storage (`storage.rules`): `…/leaveDocs/{applicantUid}/{applicationId}/{file}` — only that applicant creates (create-only: no overwrite/delete), only they and reviewing admins read; PDF/JPEG/PNG ≤ 5 MB. Teachers, finance, other parents, other branches/schools cannot read.
- **A Dart ↔ rules contract test** replays the documents the Dart code actually writes through the real rules (`leave-contract.test.mjs`). It caught two production bugs the hand-built rules tests missed (see §12).

### What rules cannot do (honest limits)
1. **Counted dates** (`countedDateKeys`) are not checked against the holiday calendar — that needs reads per date (over the per-request limit). Rules do check that units equal 2 × the number of listed dates, the dates sit inside the range and the cap holds. A malicious applicant could list fewer/different dates; a reviewer sees the figures before approving. A trusted backend (Cloud Function) would recompute them.
2. **Monthly accrual-to-date** is enforced by the client and the reviewer; rules enforce the **whole-year ceiling** (`entitlement + carry + adjustments − consumed`).
3. A reviewer who holds the permission can approve something they should not — mitigated by the history record naming them, not prevented.
4. Client transactions do not protect against a malicious privileged client; the rules above are the real guard. Anything stronger (recomputing leave from the calendar server-side) needs trusted backend execution, which this project does not have.

## 10. Indexes added (26 → `firestore.indexes.json` now 56)
leaveApplications: (status, createdAt↓), (subjectKind, createdAt↓), (subjectKind, status, createdAt↓), (subjectKind, subjectId, createdAt↓), (applicantUserId, createdAt↓), (subjectKind, typeId|classId|sectionId, createdAt↓), (subjectKind, status, typeId|classId|sectionId|subjectId, createdAt↓), (subjectKind, status, startDateKey), (subjectKind, status, typeId|classId|subjectId, startDateKey), (subjectKind, status, classId, sectionId, startDateKey); leaveCalendar: (subjectKind, endDateKey), (… classId|sectionId|subjectId, endDateKey); leaveLedger: (staffId, at↓), (balanceId, at↓); leaveHistory: (applicationId, revision); notifications: (audience, recipientUserId, createdAt↓), (audience, createdAt↓). **Not exercised by the emulator** — deploy and watch for "index required".

## 11. Screens
Leave dashboard (counts via `count()`), applications list/queue with server-side filters (kind, status, type, class, section), application detail (details, documents, history, actions), on-behalf form, leave types & policy, staff balances + ledger + adjust/carry-forward, leave calendar (month grid, day detail), reports (status counts, usage by type, by section, staff balance table), my leave (parent: child chips + applications; staff: balances + applications), apply form (counted days, skipped dates, balance, warnings before submit), notifications. Mobile gets "More" in the bottom bar; no screen overflowed at 360/800/1400 px in tests.

## 12. Tests
- Unit (`test/leave/`, 56): units, type validation, day calculator (weekends, holidays, special working days, half days, civil dates), overlap, workflow authorization and self-approval, balance model and accrual, submission planner, attendance overlay, Dart→rules contract export.
- Widget (`test/widget/leave_ui_test.dart`, 48): route/nav matrix per role, dashboard, list filters/empty/error, review actions per role/ownership, confirmation + reasons, double-tap = one request, stable application id on retry, parent applies for linked child only, staff balance blocking, types/policy form, calendar, reports, notifications, responsive widths.
- Attendance integration (`attendance_ui_test.dart`, +5): annotation never marks/changes anyone; half-day label; cancelled hidden; finalized stays; lookup failure never blocks.
- Rules (`leave-rules.test.mjs` 33, `leave-storage-rules.test.mjs` 3, `leave-contract.test.mjs` 1): tenant and branch isolation, parent-child, staff self-service, privacy, validation, overlap (incl. concurrent), half days, lock forgery, self-approval, concurrent decisions (exactly one wins), consume once, ceiling at approval, restore only what was consumed, adjustments, types, notifications, query shapes, document access; **mutation-checked** (10 rule mutants, all killed).
- Bugs found by tests while building (fixed): approval could skip the balance move; any school member could plant a notification; Storage overwrite was allowed; **Dart did not write `decidedBy` so every submission was refused** (contract test); **history query unprovable for applicants** (query-shape test).
- Combined rules suite now runs files serially (`--test-concurrency=1`); in parallel the shared emulator made unrelated Storage tests flaky.

## 13. Deploy
1. `firebase deploy --only firestore:rules,firestore:indexes,storage` (wait for indexes).
2. In **Leave types & policy**: create student and staff leave types. Nothing is seeded or hard-coded.
3. Optionally enable "office staff may file student leave on behalf".
4. Staff balances appear on first approval or when an admin adjusts; use "Carry forward" at year start.
5. Staff must have a staff record linked to their login (M4) to apply; parents need an ACTIVE portal link (M3).

## 14. Known limitations / not verified
1. No end-to-end run against a real Firebase project; indexes unexercised; Dart repositories are verified against the rules through the contract test and against fakes, not against a live backend.
2. §9 limits: counted dates and monthly accrual-to-date are not rules-enforced.
3. No pending-day reservation policy (pending leave is informational).
4. No designated-approver role (reviewers = admins); no hierarchy/multi-level approval.
5. Admin-on-behalf UI exists for **students** only; staff on behalf is allowed by the rules (with the setting) but has no screen.
6. Teachers read all students' calendar entries in their branch (minimal data), not only their own class.
7. Cancelling approved leave restores the **whole** application, even if partly elapsed; correct with an adjustment if needed.
8. Applications must lie inside one academic year and span at most 60 days.
9. A linked parent who is not the applicant can read the application but cannot open its attachments (Storage allows the applicant and reviewers only).
10. Reviewers' notifications are a shared feed (no per-user read state); nothing external is sent.
11. "Attendance-related leave summary" is approved leave days per section for a period; there is no combined attendance-percentage-with-leave figure.
12. iOS cannot be built in this environment (iOS 26.5 platform not installed).
13. Earlier disclosed: M4 `dart format` churn on pre-existing files.
