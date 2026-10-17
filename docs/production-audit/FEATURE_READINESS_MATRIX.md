# Feature readiness matrix

Rating: **A** ready (verified), **B** ready with conditions, **C** gaps remain, **D** blocked, **U** unverified. "Evidence" = what was actually run/read; rules coverage refers to `firestore-tests` (437 passing).

| Area / feature | Status in code | Evidence | Tests | Rating | Key issues |
|---|---|---|---|---|---|
| Email/Google login, logout, session restore | Implemented | `tenantContextProvider`, router redirects, `session_and_startup_test` | unit + widget | B | ROUTE-2 (no deep-link restore), NOTIF-1 (device cleanup), STATE-3 |
| Phone OTP login | Implemented, off until Meta secrets set | `functions/otp.js` (+168 test lines) | node tests | C | SEC-2/3 (App Check, lock-out, TTL); WhatsApp template/secrets UNKNOWN |
| Disabled/suspended users | Rules + `login` gate | `login-access-rules` tests | rules | B | NOTIF-2 (still pushed) |
| School registration / setup | Implemented | self-signup batch rules | rules | B | SEC-6 (no spam control) |
| Branches, per-branch staff roles, branch switcher | Implemented this session | `multi-branch-*` tests | rules/node/widget | B | STATE-6 |
| Academic years (school-wide registry + branch copies) | Implemented this session | `school-year-rules` | rules/widget | C | **ACAD-1** date storage |
| Students: admit/edit/search/status | Implemented | repositories, rules | widget + rules | C | ACAD-2, STATE-1, UI-1, PERF-3 |
| Student in-branch transfer / branch transfer | Implemented | write-plan contract | rules | C | ACAD-7 (race), ACAD-2 |
| Parents & links, portal access, `parentAccess` | Implemented | parent-scope tests | rules | B | PERF-2 |
| Staff / teachers / assignments | Implemented | `staff-rules` | rules | B | CFG-6 (index), ACAD-15 |
| Attendance (student/staff) | Implemented, transactional register save | `attendance_register_transaction.dart` | unit + rules | B | ACAD-9 (rules trust doc fields); no contract fixture |
| Holidays / working days / calendar | Implemented | `validHoliday`, `validWorkingDays` | rules | B | ACAD-13 |
| Leave (student/staff) | Implemented, transactional decisions, ledger ids | leave contract fixtures | rules/unit | B | ACAD-1, ACAD-10 |
| Exams / marks / results / report cards | Implemented, resumable finalise | exam contract fixtures | rules/unit | C | ACAD-3, ACAD-4, ACAD-8, UI-2, PERF-1 |
| Homework & submissions | Implemented; server time decides lateness | homework contract | rules | B | ACAD-12 |
| Timetable / substitutions | Implemented; publish lock | timetable contract | rules | B | ACAD-11 |
| Fees: structures, assignments | Implemented | `firebase_fee_config_repository.dart` | rules + unit | B | — |
| Invoices (generation, numbering) | Implemented; idempotent chunks, counter in txn | `firebase_invoice_repository.dart:134-250` | unit + rules | B | OPS-4, client `issueDateKey` |
| Payments, receipts, reversals | Implemented; single txn, idempotency key, audit | `firebase_payment_repository.dart:36-330` | 33+ rules tests | B | client-supplied dates; collector-fraud is process control |
| Online payments / gateway | **Not implemented** | — | — | N/A | requires backend before launch of that feature |
| Messaging (parent–teacher) | Implemented | communication contract | rules | B | — |
| Announcements | Implemented | rules | rules | C | ACAD-6 (scheduled push) |
| Push notifications (token registry, fan-out, events) | Implemented (new) | `functions/push.js`, `devices.js`, `notify_events.js` | 132 node tests | C | **NOTIF-1, NOTIF-3**, NOTIF-2/4 |
| Dashboards / reports | Implemented | aggregate `count()`/`sum()` | widget | B | PERF-1 |
| File uploads (photos, docs, homework, leave) | Implemented | storage rules suites | rules | B | SEC-6 (SVG, orphan files); no malware scan |
| Observability (crash reporting, alerts) | Dart sink only | `monitoring_setup.dart` | unit | D | OPS-2, LOG-1 |
| Backup / restore | Documented only | docs | none | U | OPS-1 |
