# Requirements and their state

Legend: ✅ done and tested · 🟡 partly · ⬜ not started.

| # | Requirement (master prompt phase) | State |
|---|---|---|
| 1 | Phase 0 assessment documents | ✅ |
| 2 | Settings: module switch, prefixes, sources, follow-up days | ✅ (`saveAdmissionSettings`, Admission settings page) |
| 2a | Settings: open years/classes, mandatory documents, fee settings, notification preferences | ⬜ (years/classes: server supports, UI deferred — see CURRENT_ARCHITECTURE) |
| 3 | Number generation: unique, tenant-aware, transactional, retry-safe, never client-counted | ✅ enquiry numbers · 🟡 application numbers (prefix stored, generator exists, used from Phase 6) |
| 4 | Enquiry: student, guardians (up to 4), source, year/class/branch, previous school, remarks, assignment | ✅ |
| 5 | Enquiry list: search name/mobile/number; filter year, class, status, source, date; paging | ✅ · filter by assigned staff: repository supports, no UI · sorting: newest first only · export ⬜ |
| 6 | Duplicate detection (mobile + name + DOB + year), flag only | ✅ |
| 7 | Lifecycle state machine with history, reasons, no arbitrary status writes | ✅ lead stages · later statuses are reserved for their workflows (⬜) |
| 8 | Follow-ups: six types, schedule, reschedule, reassign, complete (outcome, feedback, remarks, next contact), cancel, history, dashboard (today / overdue / upcoming / mine / unassigned / completed / no follow-up) | ✅ |
| 8a | Automated reminders: due today + overdue, school time zone, no duplicates, existing notification pipeline | ✅ (in-app + push through the existing path) · email ⬜ |
| 8b | School visits (multiple per enquiry, drive VISIT_* statuses, completion notes) | ⬜ Phase 5 — a visit can be logged today as a "School visit" activity, but it does **not** move the enquiry status |
| 9 | Applications, documents, verification | ⬜ |
| 10 | Admission fees (on existing fee module) | ⬜ |
| 11 | Convert to student (idempotent) | ⬜ |
| 12 | Public enquiry portal | ⬜ |
| 13 | Notifications | 🟡 follow-up due/overdue only · new enquiry, assignment, application, approval, confirmation ⬜ |
| 14 | Dashboard counts | ✅ counts and conversion rate · reports and CSV/PDF export ⬜ |
| 15 | Responsive UI for implemented screens | ✅ (tests at 320/390/820/1440 px and 1.5× text) |
| 16 | RBAC in UI and backend | ✅ for implemented operations |
| 17 | Rules, indexes, deletion-matrix entries | ✅ |

## Definitions
- **Active enquiry:** status not closed and not `NOT_INTERESTED` (`AdmissionStatus.isOpen`).
- **Conversion rate:** `ADMISSION_CONFIRMED ÷ all enquiries recorded` in the branch, over all time.
  (A date or academic-year filter arrives with Phase 11.)
