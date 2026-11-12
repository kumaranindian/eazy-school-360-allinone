# Implementation status

Branch `feature/admission-management`. **Not deployed anywhere.** Last verified 2026-11-12.

## Completed (Phases 0–4)
- Phase 0: this documentation set.
- Phase 1: admission settings (module switch, prefixes, sources, follow-up days, **reminder switch and time**) and
  transactional number generation.
- Phase 2: enquiry create / edit / assign / list (search + filters + paging) / details, duplicate flagging.
- Phase 3: status state machine for the lead stages, reasons, ON_HOLD/RESUME, immutable history.
- **Phase 4: follow-up management** — six activity types; schedule, reschedule, reassign, complete (outcome, parent
  feedback, internal remarks, optional next contact in the same transaction) and cancel; append-only activity
  history; the enquiry's next follow-up date derived from its open activities; closing an enquiry cancels its open
  follow-ups; follow-up dashboard (today, overdue, upcoming, mine, unassigned, completed, no follow-up) with
  server-side counts; hourly reminders (due today, overdue) at each school's own local time, deduplicated, through
  the existing notification/push path; notification tap opens the enquiry.
- Responsive UI for: Admission dashboard, Follow-ups, Enquiry list, New/Edit enquiry, Enquiry detail (Overview,
  Activities, Timeline, Internal notes), Admission settings.

## Not started
Phases 5–16: school visits (as their own workflow driving the VISIT_* statuses), applications, documents, admission
fees, student conversion, public portal, remaining notifications, reports/export, the Application/Documents/Fees
tabs, an "Admission staff" role, settings UI for open years/classes. See IMPLEMENTATION_PLAN.

## Files (phase 4)
- Created: `functions/admission_activities.js` (+ `.test.js`), `lib/features/admission/domain/admission_activity.dart`,
  `presentation/pages/follow_ups_page.dart`, `presentation/widgets/activity_{widgets,dialogs}.dart`.
- Modified: `functions/admission.js` (settings fields, derived-date guard, closing cancels follow-ups, exports),
  `functions/index.js` (5 callables + scheduled reminders), `functions/deletion_processor.js` (`assignedTo`,
  `completedBy`, 2 collections), `firestore.rules` (2 read-only matches), `firestore.indexes.json` (5 indexes),
  `lib/core/routing/app_routes.dart`, `lib/features/notifications/domain/feed_item.dart` (route for the new
  notification types), repository/provider/pages under `lib/features/admission`, enquiry form (derived follow-up date;
  date pickers now use the school's today), tests and docs.

## Collections / indexes / functions / security
See DATABASE_DESIGN, API_DESIGN, SECURITY_DESIGN. New this phase: `admissionActivities`, `admissionActivityHistory`
(read-only rules; callables write), callables `schedule/reschedule/reassign/complete/cancelAdmissionActivity`, scheduled
function `admissionFollowUpReminders`, notification types `ADMISSION_FOLLOWUP_DUE` / `ADMISSION_FOLLOWUP_OVERDUE`.

## Verification (this branch, phase 4)
| Check | Result |
|---|---|
| `flutter analyze` | clean |
| `dart format --set-exit-if-changed` | clean |
| `flutter test` (full) | **1,983 pass, 0 fail** (28 admission domain, 77 admission UI) |
| `functions` `npm test` | 355 / 355 pass (34 follow-up, 23 enquiry) |
| Firestore rules (emulator, full suite) | 487 pass, 22 fail — **all 22 are the Storage-rules tests that also fail on a clean `develop` checkout in this sandbox** (same set as before phase 4; `storage.rules` unchanged); all Firestore-rules tests pass incl. 8 admission ones |
| `tool/*.test.js`, `build_rules.js --check` | pass; built rules 148 KB of 256 KB |
| `flutter build web` | **not run** for this branch |

## Known limitations
- The repository's Firestore queries and index set are untested against a real/emulated query run
  (see TEST_PLAN). Verify on dev first.
- Enquiries are read by the school admin and the branch admin; the platform admin sees the screens but,
  with no school, the page says "No branch found".
- Assignment lists staff of the branch that have a login (first 100 active).
- Follow-up queries (bucket lists and the `isNull` + `whereIn` count) and the 5 new indexes are untested against a real/emulated query run: deploy to dev first.
- Reminders: a school with no branch admin and an unassigned activity notifies its school admins; email reminders are not built; the scheduled job is untested deployed.
- Activity history is stored and enforced but the app shows only each activity's own record (reschedule count, outcome); there is no per-event history viewer yet.
- A "School visit" activity does not yet move the enquiry to VISIT_SCHEDULED/VISIT_COMPLETED (Phase 5).
- The list shows newest first only; filter by assigned staff has no UI.
- Admission settings cannot restrict academic years/classes from the UI.

## Deployment prerequisites
DEPLOYMENT_GUIDE: indexes → functions → built rules → app, dev first, explicit approval for prod.
