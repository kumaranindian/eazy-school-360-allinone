# Database design

All under `schools/{schoolId}`. Documents carry `schoolId` (and `branchId`) set by the server.

## `admissionSettings/config` (school-wide)
`schoolId, version, enabled, enquiryPrefix (2-6 A-Z), applicationPrefix, sources[] (1-20),
followUpDays (1-60), academicYearIds[], classIds[], updatedAt, updatedBy`.
`version` only grows; saves may send `baseVersion` and fail with `aborted` if stale.
Absent document = defaults with `enabled: false`.

## `branches/{b}/admissionEnquiries/{id}`
`schoolId, branchId, enquiryNumber ("ENQ-2026-00001"), enquiryDate (yyyy-mm-dd, school time zone),
student{firstName,lastName,dateOfBirth,gender}, studentName, studentNameLower, academicYearId,
interestedClassId, source, guardians[{name,relationship,phone,alternatePhone,email,primary}]
(phones normalised to digits, last 10), primaryPhone, primaryGuardianName, address{line1,city,state,country},
previousSchool, previousClass, specialRequirements, remarks (internal), nextFollowUpDate,
assignedTo (uid|null), status, heldFrom (status before ON_HOLD), statusReason, duplicateOf[],
revision (1, +1 on every change), createdAt/By, updatedAt/By`.

## `branches/{b}/admissionStatusHistory/{enquiryId}__{revision}` (immutable)
`schoolId, branchId, enquiryId, revision, from (null on creation), to, reason, resumed, actorId, at`.
Written in the same transaction as the change; the id includes the revision so a retry cannot
duplicate or overwrite an entry.

## `branches/{b}/admissionSequences/{PREFIX-YEAR}` (server-only)
`{ schoolId, branchId, prefix, year, next }`. Read and incremented inside the enquiry-creating
transaction. One series per branch, prefix and year. No client rule exists (denied by default).

## `branches/{b}/admissionActivities/{id}` (phase 4)
`schoolId, branchId, enquiryId, enquiryNumber, studentName (copied for dashboard lists), type
(PHONE_CALL|WHATSAPP|EMAIL|SCHOOL_VISIT|MEETING|OTHER), scheduledDate (yyyy-mm-dd, school time zone),
scheduledTime (hh:mm|null), assignedTo, status (SCHEDULED|COMPLETED|CANCELLED), remarks, outcome,
parentFeedback, completedAt, completedBy, cancelReason, rescheduleCount, revision, createdAt/By, updatedAt/By`.
Id is `{enquiryId}__{requestId}` when the client sends an idempotency key, so a retry returns the same activity.

## `branches/{b}/admissionActivityHistory/{activityId}__{revision}` (append-only)
`schoolId, branchId, activityId, enquiryId, revision, event (CREATED|RESCHEDULED|REASSIGNED|COMPLETED|CANCELLED),
from{...}, to{...}, reason, actorId, at`. Rescheduling keeps the old date in `from`; nothing is overwritten.

## Derived fields on the enquiry
`nextFollowUpDate` (earliest open activity), `openActivityCount`, `activityCount`, `lastActivityAt` — updated in the
same transaction as the activity change. The enquiry's `revision` is **not** bumped by activity changes, and
`updateEnquiry` never overwrites `nextFollowUpDate` once `activityCount > 0`. Closing an enquiry cancels its open
activities (kept, reason "Enquiry closed") and clears the date.

## Reminder notifications
Written to `branches/{b}/notifications/{ADMISSION_FOLLOWUP_(DUE|OVERDUE)__{activityId}__{scheduledDate}__{uid}}`
with `create()` (an existing id is a no-op). Text names the enquiry **number** and kind of contact only.

## Settings added in phase 4
`remindersEnabled` (default true), `reminderTime` ("09:00", 06:00–21:00, school time zone).

## Indexes (`firestore.indexes.json`)
`admissionEnquiries`: `(assignedTo|status|interestedClassId|academicYearId|source, createdAt desc)`;
`admissionStatusHistory`: `(enquiryId, revision)`; `admissionActivities`: `(status, scheduledDate)`, `(status, assignedTo, scheduledDate)`, `(enquiryId, scheduledDate desc)`, `(status, completedAt desc)`; `admissionActivityHistory`: `(enquiryId, at desc)`. Name search uses `studentNameLower`
(single-field). Phone and number search use equality. The list sends **one** equality filter to
Firestore and applies the others in memory, so the index set stays small.

## Account deletion
`admissionEnquiries`, `admissionStatusHistory`, `admissionActivities`, `admissionActivityHistory` are scanned for uid fields (`assignedTo` and `completedBy` were added to the processor's uid list for this module; token replacement);
`admissionSettings` likewise. Prospective-family data is a school record and is kept (matrix D8/D9).
