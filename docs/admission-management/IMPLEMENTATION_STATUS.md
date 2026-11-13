# Implementation status

Branch `feature/admission-management`. **Not deployed anywhere.** Last verified 2026-11-14.

## Completed (Phases 0–6)
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
- **Phase 5: school visits** — visits are follow-ups of type School visit with a purpose (campus tour, meet the principal,
  assessment, counselling, other), booked through their own callable (`scheduleAdmissionVisit`); several per enquiry;
  date/time, assigned staff, notes, completion notes and parent feedback, rescheduling, cancellation with a reason;
  booking moves the enquiry to VISIT_SCHEDULED and completing/cancelling the last open visit moves it on
  (VISIT_COMPLETED / INTERESTED), all in the same server transaction; the enquiry **timeline now merges status changes with
  every follow-up and visit event**; a Visits tab on each enquiry, a Visits list on the follow-up dashboard, and
  visits-scheduled / visits-completed tiles on the admission home.
- **Phase 6: applications and documents** — an application is started from an enquiry (Interested / Visit scheduled / Visit completed), gets
  its own number (`APP-2026-00001`, transactional), is edited as a draft, submitted, taken into review, and approved or rejected with
  comments; each step moves the enquiry too (submitted → under review → approved / rejected). Documents (birth certificate, student and
  parent photographs, transfer certificate, previous records, address proof, plus school-defined types) are uploaded in three server-checked
  steps (request → bytes to the approved path → server confirms size, type **and file signature**), verified or rejected with a reason,
  removed while the application is open, viewed through the authenticated Storage SDK (no shareable link), and unconfirmed uploads are
  cleaned up daily. The school chooses which documents are required for approval and whether branch administrators may approve (default:
  school administrators only). Screens: an Application tab and a Documents tab on each enquiry, an application edit page, an Applications
  list, application events in the timeline, document and approval settings.
- Responsive UI for: Admission dashboard, Follow-ups, Enquiry list, New/Edit enquiry, Enquiry detail (Overview,
  Activities, Visits, Timeline, Internal notes), Admission settings.

## Not started
Phases 7–16:  documents, admission
fees, student conversion, public portal, remaining notifications, reports/export, the Application/Documents/Fees
tabs, an "Admission staff" role, settings UI for open years/classes. See IMPLEMENTATION_PLAN.

## Files (phase 6)
- Created: `functions/admission_applications.js` (+ `.test.js`), `firestore-tests/admission-storage-rules.test.mjs`,
  `lib/features/admission/domain/admission_application.dart`, `presentation/pages/{application_form_page,applications_page}.dart`,
  `presentation/widgets/{enquiry_application_tabs,application_widgets}.dart`, `presentation/providers/document_picker.dart`.
- Modified: `functions/admission.js` (document types, settings, lifecycle, closing hook), `functions/index.js` (9 callables + daily cleanup),
  `functions/storage_adapter.js` (`stat`, `head`), `functions/deletion_processor.js`, `firestore.rules` (+3 read-only matches),
  **`storage.rules` (+ `admissionDocs`)**, `firestore.indexes.json` (+2), `Permission.decideAdmissions`, app routes, the repository,
  providers, settings page, enquiry detail, timeline, tests and docs.

## Files (phase 5)
- Modified: `functions/admission_activities.js` (visit booking, status effects, history `type`/`purpose`), `functions/admission.js`
  (lifecycle: NEW → VISIT_SCHEDULED, VISIT_COMPLETED → VISIT_SCHEDULED), `functions/index.js` (`scheduleAdmissionVisit`),
  `firestore.indexes.json` (+1), the activity domain/repository/providers/widgets/dialogs, enquiry detail (Visits tab, merged
  timeline), follow-up dashboard, admission home, tests and docs.
- Created: `lib/features/admission/domain/admission_timeline.dart`.
- No change to `firestore.rules` (same collections).

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

## Verification (this branch, phase 6)
| Check | Result |
|---|---|
| `flutter analyze` | clean |
| `dart format --set-exit-if-changed` | clean |
| `flutter test` (full) | **2,047 pass, 0 fail** (42 admission domain, 127 admission UI) |
| `functions` `npm test` | 402 / 402 pass (33 application and document, 47 follow-up and visit, 23 enquiry) |
| Firestore rules (emulator) | `admission-rules.test.mjs`: 10 / 10 pass (incl. applications, history, documents). Full suite last run in phase 4: 487 pass, 22 fail — **all 22 are the Storage-rules tests that also fail on a clean `develop` checkout in this sandbox** (same set as before phase 4; `storage.rules` unchanged); all Firestore-rules tests pass incl. 8 admission ones |
| `tool/*.test.js`, `build_rules.js --check` | pass; built rules 148 KB of 256 KB |
| **Storage rules** (`admission-storage-rules.test.mjs`) | **NOT verified.** 3 of 6 pass, but those are the deny-cases that also pass when nothing works; the allow-cases fail here, exactly as the existing Storage suites do in this sandbox (the Storage emulator's cross-service lookup does not work in it). The rule text compiles and the built size is 11.5 KB. **Run this file in CI before deploying Storage rules.** |
| `flutter build web` | **not run** for this branch |

## Phase 7 — admission fees (done)
- Decision (confirmed by the product owner): applicant-level fee records that use the Fees module's receipt series and
  money rules; the paid amounts are carried into the student's fee records at conversion (phase 8). No gateway.
- Backend: `functions/admission_fees.js` (set / record payment / refund / waive / cancel), 5 callables, rules (read-only),
  index, account-deletion decisions (D10). UI: a **Fees** tab on the enquiry (categories, totals, payments with receipt numbers).
- Tests: functions `admission_fees.test.js` (9), rules (`admission-rules` 11 passing on the emulator), Dart domain (4) and
  widget (10) tests; the fee-structure link is validated server-side but there is no picker in the UI yet (amount is typed).
- Not done: Finance role view, posting into the student ledger (phase 8), fee receipt PDF for admission payments.

## Phase 8 — convert to student (done)
- `functions/admission_conversion.js` (`convertAdmissionToStudent`), all-or-nothing in one transaction; `admissionConversions` record
  (read-only rules, account-deletion row D11); UI: a *Convert to student* card on an approved application (section, roll number,
  unpaid-fee confirmation) and, afterwards, the admission number and parents linked.
- Tests: functions `admission_conversion.test.js` (12: full write set, idempotent repeat, concurrency, number skipping, parent reuse,
  state/authority/placement/fee gates), rules (12), Dart widget tests (6).
- **Fee carry-over is recorded, not posted:** the Fees module has no credit/advance concept and invoices are generated from student
  fee assignments, so the paid admission amounts (with receipt numbers) are stored in the conversion record and linked to the student
  (`admissionFees.studentId`); they are NOT yet applied against the student's first invoice. This needs a decision on a credit concept.
- Not done: no student fee assignment is created (assign fees in the Fees module as usual), no parent login, no photo/document copy
  to the student record, no notification (phase 10).

## Phase 9 — public enquiry page (done)
- Backend `functions/admission_public.js` (`getAdmissionPortal`, `submitPublicAdmissionEnquiry`), settings (`publicPortal`, unique page address,
  versioned consent) in `saveAdmissionSettings`, deletion-matrix row D12. Route `/admission/:slug` (open to signed-out visitors), the public form,
  and a *Public enquiry page* card in Admission settings.
- Tests: functions `admission_public.test.js` (16), rules (+2: server-only bookkeeping, signed-out cannot touch enquiries), Dart: 8 public-form widget tests,
  1 settings widget test, 3 domain tests.
- **Not verified here / needs your action before real use:** App Check enforcement and a reCAPTCHA web key must be configured (otherwise only the
  honeypot and rate limits protect the page); the Turnstile verifier is unit-tested with a fake fetch only; the Firestore TTL policy on
  `publicLimits.expireAt` must be enabled; the Flutter page has no Turnstile widget; the web build and a deployed round trip were not run.
- Not done: staff notification of new public enquiries (phase 10), a "Public portal" badge in the enquiry list, a QR/share link helper.

## Phase 10 — notifications (done)
- `functions/admission_notify.js` + two triggers (`retry: true`), six switches in Admission settings, tap-through routing for the new notice types.
- Tests: functions `admission_notify.test.js` (12), Dart domain (2) and widget (1) tests; the settings test viewport was made taller for the longer page.
- Honest limits: the triggers and the push delivery were never run deployed; parents usually have no login at conversion, so the parent notice reaches only
  families who already have one; there is no email/WhatsApp message to parents or applicants (push/in-app only); no per-user preference screen.

## Phase 11 — dashboard and reports (done)
- `functions/admission_reports.js` (`getAdmissionReport`), a **Reports** page (route `/admissions/reports`, linked from the admission dashboard), CSV (copied) and PDF (print) export.
- Tests: functions `admission_reports.test.js` (12), Dart domain (4) and widget (9) tests.
- Honest limits: the report reads up to 5,000 enquiries per branch (and every activity and fee record of the branch) on each request: fine for a school, not for very large
  data; a precomputed rollup would be the next step. Conversion is "confirmed ÷ enquiries in the filter" (no cohort tracking by date of conversion). No staff-performance
  time metrics (e.g. days to first contact) yet. The export is a clipboard CSV and a print/PDF dialog (the app's existing pattern), not a file download. The report
  query has not been run against the emulator or deployed. Admissions headline counts on the dashboard are unchanged (server `count()`).

## Phase 12 — remaining UI (done)
- Fees tab: *Set amount* offers the branch's active **ADMISSION fee structures** for the applicant's year (all classes, or their class); choosing one fills the amount and sends
  `feeStructureId` (the server already validated it); the amount can still be edited.
- Enquiry list: a **Website** badge for enquiries from the public page (`channel`), and an **Assigned to** filter (the query plan already supported it).
- Converted applications show **Open student** (links to the student profile).
- Admission settings: **Open for admissions** (academic years and, within chosen years, classes) replaces the old "cannot restrict from the UI" limitation; un-choosing a year drops its classes.
  The server already refuses enquiries for years/classes that are not open (`validateEnquiry`).
- No backend change in this phase. Tests: Dart widget tests for the structure picker (filtering by category, status and class; link kept after editing the amount), the badge, the assignee filter,
  Open student and the year/class limits.
- Not done: filter by channel (a new index would be needed), "unassigned" in the assignee filter, a student link for enquiries converted outside this flow, per-user dashboard widgets.

## Known limitations (phase 6)
- The Storage rules are untested in an emulator (see above); the real upload → confirm round trip and `FirebaseAdmissionDocumentStore` are untested.
- (Phase 7 added fees.) No conversion to a student (phase 8): an APPROVED application is the end of the road for now.
- The application edit form covers the essential fields (not every enquiry field, e.g. no source or internal remarks); a reviewer cannot send a draft back for changes (they reject documents instead).
- Approving needs the school's required documents verified; there is no per-document expiry or duplicate-file detection.
- PDF viewing uses the `printing` package's preview; it is not covered by a widget test.
- Parents cannot upload or see anything (a self-service portal is out of scope per the brief).

## Known limitations
- The repository's Firestore queries and index set are untested against a real/emulated query run
  (see TEST_PLAN). Verify on dev first.
- Enquiries are read by the school admin and the branch admin; the platform admin sees the screens but,
  with no school, the page says "No branch found".
- Assignment lists staff of the branch that have a login (first 100 active).
- Follow-up queries (bucket lists and the `isNull` + `whereIn` count) and the 5 new indexes are untested against a real/emulated query run: deploy to dev first.
- Reminders: a school with no branch admin and an unassigned activity notifies its school admins; email reminders are not built; the scheduled job is untested deployed.
- The status follows visits only while the enquiry is at VISIT_SCHEDULED: after a manual move (e.g. to INTERESTED) a later visit completion does not set VISIT_COMPLETED (by design, see WORKFLOWS). Booking a visit on an ON_HOLD / NOT_INTERESTED enquiry is refused until it is resumed/reopened.
- A visit's visitors (who is coming) and a parent-facing confirmation are not modelled; parent notifications are Phase 10.
- The list shows newest first only.

## Deployment prerequisites
DEPLOYMENT_GUIDE: indexes → functions → built rules → app, dev first, explicit approval for prod.
