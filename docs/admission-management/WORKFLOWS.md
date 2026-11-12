# Enquiry lifecycle

Primary path: NEW → CONTACTED → INTERESTED → VISIT_SCHEDULED → VISIT_COMPLETED →
APPLICATION_SUBMITTED → UNDER_REVIEW → APPROVED → ADMISSION_CONFIRMED.
Alternates: ON_HOLD, REJECTED, WITHDRAWN, NOT_INTERESTED.

**Closed (no way out):** REJECTED, WITHDRAWN, ADMISSION_CONFIRMED.
**Reasons:** required (≥3 characters) for REJECTED and WITHDRAWN; optional otherwise.
**Hold:** ON_HOLD remembers the status it came from (`heldFrom`); `RESUME` returns to it. From hold
the only other moves are NOT_INTERESTED, REJECTED, WITHDRAWN.
**Reopen:** NOT_INTERESTED → CONTACTED or INTERESTED.

## Who sets what
- **By a person today (lead stages):** CONTACTED, INTERESTED, NOT_INTERESTED, ON_HOLD (+RESUME),
  REJECTED, WITHDRAWN.
- **Reserved for their own workflow (not settable directly, the server refuses):** VISIT_SCHEDULED,
  VISIT_COMPLETED (Phase 5), APPLICATION_SUBMITTED, UNDER_REVIEW, APPROVED (Phase 6),
  ADMISSION_CONFIRMED (Phase 8, conversion). `applyStatus` in `functions/admission.js` is the
  shared transactional helper those phases will call.

The table of what the UI offers from each status is pinned identically in
`admission.test.js` and `admission_domain_test.dart`.

## Follow-ups (phase 4)
SCHEDULED → COMPLETED (outcome required; may plan the next contact in the same transaction) or CANCELLED (reason
required). A SCHEDULED activity can be rescheduled (date/time, optional reason) or reassigned any number of times;
each change appends a history entry and keeps the old values. COMPLETED and CANCELLED are final.
Buckets (school-local "today"): **Today** (open, dated today), **Overdue** (open, earlier), **Upcoming** (open, later),
**Mine** (open, assigned to me), **Unassigned** (open, nobody), **Completed**, plus **No follow-up** (open enquiries with
no planned date). Closing an enquiry cancels its open follow-ups.
Reminders: DUE on the day, one OVERDUE per activity per scheduled date; a rescheduled activity gets one fresh notice.

## School visits (phase 5)
A visit is a follow-up of type School visit with a **purpose** (campus tour, meet the principal, assessment, counselling,
other), booked through its own call because it also moves the enquiry:

| Event | Enquiry status |
|---|---|
| Book a visit while NEW / CONTACTED / INTERESTED / VISIT_COMPLETED | → VISIT_SCHEDULED (history reason "Visit scheduled") |
| Book another visit while already VISIT_SCHEDULED | unchanged; no extra history line |
| Complete a visit, no other visit open | VISIT_SCHEDULED → VISIT_COMPLETED ("Visit completed") |
| Complete a visit, another still open | unchanged |
| Cancel the last open visit, no visit ever completed | VISIT_SCHEDULED → INTERESTED ("Visit cancelled") |
| Cancel the last open visit, an earlier visit was completed | VISIT_SCHEDULED → VISIT_COMPLETED |
| Reschedule / reassign | unchanged (a timeline entry records both dates / people) |
| Enquiry closed | open visits are cancelled ("Enquiry closed") |

Visits cannot be booked on enquiries that are ON_HOLD, NOT_INTERESTED, in an application stage, or closed (resume or reopen
first). The status only follows visits **while it is VISIT_SCHEDULED**: if someone moves the enquiry elsewhere by hand
(e.g. ON_HOLD), completing the visit never overrides that; resuming returns to the status it was on. The lifecycle table
gained NEW → VISIT_SCHEDULED and VISIT_COMPLETED → VISIT_SCHEDULED; neither is settable by hand.

The enquiry **timeline** merges the status history with every follow-up and visit event (booked, rescheduled from/to,
reassigned, completed, cancelled with reason), newest first.

## Applications and documents (phase 6)
**Application:** DRAFT → SUBMITTED → UNDER_REVIEW → APPROVED | REJECTED (WITHDRAWN when the enquiry closes). Each step also moves the enquiry:

| Application | Enquiry |
|---|---|
| create (from Interested / Visit scheduled / Visit completed) | unchanged |
| submit | → APPLICATION_SUBMITTED |
| start review | → UNDER_REVIEW |
| approve (all required documents VERIFIED) | → APPROVED |
| reject (comment required) | → REJECTED (open follow-ups and visits cancelled) |
| enquiry withdrawn / rejected by hand | application → WITHDRAWN / REJECTED |

A draft can be edited; after submission it is locked. Comments are internal and kept in the history. An enquiry that is ON_HOLD cannot submit (resume first).

**Document:** request → UPLOADING → (bytes uploaded, server confirms) → UPLOADED → VERIFIED | REJECTED(reason); any listed document can be REMOVED while the application is open;
an unconfirmed upload becomes ABANDONED after 24 h. A rejected or removed document does not count toward "required"; a replacement does. After approval or rejection documents are frozen.

## Numbers
`ENQ-<year>-<5 digits>` per branch and year, year from the enquiry date. Generated in the creating
transaction (`maxAttempts: 10` for bursts of walk-ins). Concurrency test: six parallel creates
produce six distinct consecutive numbers.

## Duplicates
On create: enquiries in the branch with the same normalised primary mobile and academic year are
fetched (≤25), then compared on normalised name and date of birth. Matches are stored in
`duplicateOf` (≤5) and shown as a warning; nothing is merged or blocked.
