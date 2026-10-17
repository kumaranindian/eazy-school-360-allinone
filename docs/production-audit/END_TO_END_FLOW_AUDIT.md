# End-to-end flow audit

**No journey was executed against real Firebase projects, real devices or the deployed web app** (no credentials, no device, no network to Firebase in the audit sandbox). Results below are from code tracing plus the automated suites (unit, widget, Firestore/Storage emulator, Node). "Traced" = code read end-to-end; "Automated" = covered by passing tests; "NOT RUN E2E" applies to every row.

Legend: ✔ no defect found, ⚠ defect(s) found (IDs), ✘ blocked.

## Admin / school admin
| Journey | Result |
|---|---|
| Register school → create branch → set up years/classes/subjects | ✔ traced, automated (rules + widget). ⚠ ACAD-1 once school years are used; first-admin creation is a manual console step |
| Open a school year in branches | ⚠ new this session; ACAD-1 storage shape |
| Add staff → give login → teacher assignments | ✔ automated; ⚠ CFG-6 (combined filters), NOTIF-2 |
| Multi-branch staff (per-branch role, switcher) | ✔ automated; ⚠ STATE-6 |
| Admit student (+ guardian), search, edit, status | ⚠ UI-1, ACAD-2, STATE-1, PERF-3 |
| Move student between branches | ✔ contract replay; ⚠ ACAD-2 (destination admission number) |
| Disable a user / sign out all devices | ✔ rules refuse immediately; ⚠ NOTIF-1/2 (pushes continue) |

## Finance
| Journey | Result |
|---|---|
| Fee structures → assignments → generate invoices | ✔ traced; idempotent chunks; ⚠ OPS-4 (counter ceiling), client issue date |
| Collect payment (retry/double-tap/two cashiers) | ✔ traced + rules tests: single txn, idempotency key, balance re-check |
| Receipt print | ✔ traced (`pdf`/`printing`) — PDF output not visually verified here |
| Reversal / refund | ✔ traced: one txn, audit in-commit, reason required; ⚠ reversal date from device clock |
| Parent views fees | ✔ rules; read-only |

## Teacher / staff
| Journey | Result |
|---|---|
| Mark attendance (single section) | ✔ transactional with revisions; ⚠ ACAD-9 (forged record can block) |
| Leave apply / approve / cancel | ✔ transactional; ⚠ ACAD-1 (last day rejected in IST), ACAD-10 |
| Marks entry → submit → approve → finalise → publish | ⚠ ACAD-3, ACAD-4, ACAD-8, UI-2, PERF-1 |
| Homework create / review | ✔ |
| Timetable publish / substitution | ✔; ACAD-11 potential |
| Students (assigned sections only) | ✔ rules; teacher list screen automated |
| Messaging a parent | ✔ |

## Parent
| Journey | Result |
|---|---|
| Sign in (email/Google/OTP) → children list | ✔ rules; OTP unverified (Meta secrets) |
| View child attendance/homework/timetable/results/fees | ✔ rules (class/section scoped via `parentAccess`) |
| Apply for leave | ⚠ ACAD-1 (year bounds) |
| Receive notices & push | ⚠ NOTIF-1/3/4, ACAD-6 |
| Several children in several branches | ✔ traced (collection-group links) |
| Browser refresh on a deep link | ⚠ ROUTE-2 |
| Offline / permission-denied on a screen | partly traced; error views exist, several swallowed errors (UI-2, STATE-2) |

## Cross-cutting
Sign-out / account switch: tenant context rebuilds on auth change (automated `session_and_startup_test`); ⚠ NOTIF-1, STATE-3, STATE-6, STATE-7. Network loss, lost response after a successful write and app-kill mid-operation were **traced** for payments (idempotent) and **not tested**.
