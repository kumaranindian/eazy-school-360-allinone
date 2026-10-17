# Firebase & database audit

## Schema & rules coverage
* Strict hierarchy `schools/{s}/branches/{b}/<collection>`; 84 `match` blocks; flat `/users/{uid}` with `schoolId`, `branchId`, `role`, `status`, `login`, `branchRoles`, `linkedParentId`. School-level collections: `authSettings`, `authAudit`, `branchAccessAudit`, `studentTransfers`, `academicYears` (registry).
* Every collection written/read by `lib/` and `functions/` has a rule (script cross-check of `.collection('…')`/`collectionGroup('…')` literals vs `match` names: only `noticeReads`, `preferences` unmatched at top-level, both matched under `users/{uid}`; `devices`, `otpChallenges`, `otpRate` are Admin-SDK-only and fall under default-deny).
* Immutable fields via `changedOnly([...])` allow-lists; state transitions enforced for exams, leave, homework, announcements, transfers; audit fields (`createdAt == request.time`, `createdBy == auth.uid`) on creates.
* **Size (SEC-1):** 223,727 B (~85 % of 262,144). Tests run in the emulator, which does not enforce the release-size limit — deployability is **UNKNOWN until `--dry-run`/release** on dev and prod. The team's own tool documents refused releases.
* **Evaluation budget:** the suite exercises rules with the emulator's access-call limits (10 per request, 20 per batch); hot paths using many `get()`s (attendance, announcements) are covered by tests but real-world quota behaviour is **NOT MEASURED**.
* `fieldOverrides`: TTL on `pushDeliveries.expireAt`; collection-group `devices.token`; `invoices.dueDateKey`. Whether TTL is *enabled* in the console and whether the dev/prod indexes are deployed is UNKNOWN.

## Indexes
91 composite + 3 overrides, version-controlled. Static review found **likely missing**: staff list combinations (CFG-6); possibly `leaveApplications` (`subjectKind, startDateKey`) for the sum aggregate without `status` (POTENTIAL). The emulator does not enforce indexes, so every new query shape needs a manual dev-project check; a CI step cannot catch this today.

## Integrity
| Topic | Finding |
|---|---|
| Unique business keys | staff codes ✔ (reservation docs); **admission numbers ✘** (ACAD-2); fees invoice/receipt numbers ✔ (`invoiceNumbers/receiptNumbers` create-only + counter in same txn) |
| Orphans / partial writes | marks save non-atomic (ACAD-3); staff status change (ACAD-15); admission without guardian link reports success (UI-1); invoice-generation audit entry best-effort |
| Denormalisation | `students.current*` cache vs `academicRecords` (race ACAD-7); `parentAccess`/`teacherAccess` derived and fail-closed; `approvedSheets` counter (ACAD-4); invoice totals reconciled by `InvoiceReconciler` |
| Time | academic-year timestamps vs date keys (ACAD-1); client device date keys on fees and leave decisions |
| Deletion & retention | no hard deletes anywhere (rules `allow delete: if false` on business data); no retention policy or TTL except `pushDeliveries`; `otpChallenges/otpRate` grow unbounded (SEC-3) |

## Cost / scale risks (estimates marked E)
* `feeDueReminders`: one collection-group scan across **all** tenants with `limit(2000)` (SEC-4).
* Finalise results ≈ one range read per student (E: 120 students ≈ 25 k reads) (PERF-1).
* *Refresh parent access*: E: 2–5 k parents ≈ 5–15 k sequential round-trips (PERF-2).
* Push fan-out: per-recipient device reads, capped at 2,000 (NOTIF-4).
* Dashboards/reports use `count()`/`sum()` aggregates; list pages are paginated (`limit`), except the two older roster pages that mis-handle paging (STATE-1).

## Backup / restore
No PITR, scheduled backups, storage versioning or restore drill is configured in the repository; the procedure is documented (`docs/milestone-12a-blocker-closure.md` §7) but **never executed**. Status: UNKNOWN — REQUIRES VERIFICATION in each Firebase project. A release cannot be recommended until PITR is enabled and one restore into a scratch database has been rehearsed (OPS-1).
