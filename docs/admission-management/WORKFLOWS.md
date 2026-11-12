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

## Numbers
`ENQ-<year>-<5 digits>` per branch and year, year from the enquiry date. Generated in the creating
transaction (`maxAttempts: 10` for bursts of walk-ins). Concurrency test: six parallel creates
produce six distinct consecutive numbers.

## Duplicates
On create: enquiries in the branch with the same normalised primary mobile and academic year are
fetched (≤25), then compared on normalised name and date of birth. Matches are stored in
`duplicateOf` (≤5) and shown as a warning; nothing is merged or blocked.
