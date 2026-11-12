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
scheduledTime (hh:mm|null), purpose (visits only: CAMPUS_TOUR|MEET_PRINCIPAL|ASSESSMENT|COUNSELLING|OTHER), assignedTo, status (SCHEDULED|COMPLETED|CANCELLED), remarks, outcome,
parentFeedback, completedAt, completedBy, cancelReason, rescheduleCount, revision, createdAt/By, updatedAt/By`.
Id is `{enquiryId}__{requestId}` when the client sends an idempotency key, so a retry returns the same activity.

## `branches/{b}/admissionActivityHistory/{activityId}__{revision}` (append-only)
`schoolId, branchId, activityId, enquiryId, type, purpose, revision, event (CREATED|RESCHEDULED|REASSIGNED|COMPLETED|CANCELLED),
from{...}, to{...}, reason, actorId, at` (`type`/`purpose` say what the entry is about, so the timeline needs no second read). Rescheduling keeps the old date in `from`; nothing is overwritten.

## `branches/{b}/admissionApplications/{enquiryId}` (phase 6)
One application per enquiry; **the id is the enquiry id** (so creating it twice returns the same one). `schoolId, branchId, enquiryId,
enquiryNumber, applicationNumber ("APP-2026-00001", transactional series, prefix from settings), status (DRAFT|SUBMITTED|UNDER_REVIEW|
APPROVED|REJECTED|WITHDRAWN), source, student{...}, studentName, academicYearId, classId, guardians[], primaryPhone, address{...},
previousSchool, previousClass, specialRequirements, submissionNotes, submittedAt/By, reviewStartedAt/By, decidedAt/By, decisionComment,
revision, createdAt/By, updatedAt/By`. The student details are a **copy** of the enquiry made at creation; editing the draft never rewrites the enquiry.

## `branches/{b}/admissionApplicationHistory/{enquiryId}__{revision}` (append-only)
`event (CREATED|SUBMITTED|REVIEW_STARTED|COMMENTED|APPROVED|REJECTED|CLOSED_WITH_ENQUIRY|DOCUMENT_UPLOADED|DOCUMENT_VERIFIED|DOCUMENT_REJECTED|DOCUMENT_REMOVED),
from, to, comment, documentType, documentId, actorId, at` — every event bumps the application's revision (the entry id). Comments are internal.

## `branches/{b}/admissionDocuments/{id}`
`schoolId, branchId, enquiryId, applicationId, type, label, fileName, contentType, sizeBytes, storagePath, status
(UPLOADING|UPLOADED|VERIFIED|REJECTED|REMOVED|ABANDONED), expiresAt (UPLOADING only), uploadedAt, verifiedAt/By, rejectionReason, revision, audit`.
No file contents and **no download URL** are stored. Storage object: `schools/{s}/branches/{b}/admissionDocs/{enquiryId}/{docId}/document.{pdf|jpg|png|webp}`.

## Settings added in phase 6
`requiredDocumentTypes` (default BIRTH_CERTIFICATE, STUDENT_PHOTO), `customDocumentTypes` [{id, label}] (≤10, id 3-24 capitals/digits/_ and not a built-in),
`branchAdminsMayApprove` (default false).

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
`admissionStatusHistory`: `(enquiryId, revision)`; `admissionActivities`: `(status, scheduledDate)`, `(status, assignedTo, scheduledDate)`, `(status, type, scheduledDate)` (visits list), `(enquiryId, scheduledDate desc)`, `(status, completedAt desc)`; `admissionActivityHistory`: `(enquiryId, at desc)`; `admissionApplications`: `(status, createdAt desc)`; `admissionApplicationHistory`: `(enquiryId, at desc)`. Name search uses `studentNameLower`
(single-field). Phone and number search use equality. The list sends **one** equality filter to
Firestore and applies the others in memory, so the index set stays small.

## Account deletion
`admissionEnquiries`, `admissionStatusHistory`, `admissionActivities`, `admissionActivityHistory`, `admissionApplications`, `admissionApplicationHistory`, `admissionDocuments` are scanned for uid fields (`assignedTo` and `completedBy` were added to the processor's uid list for this module; token replacement);
`admissionSettings` likewise. Prospective-family data is a school record and is kept (matrix D8/D9).

## Admission fees (phase 7)
An applicant is not a student, and the Fees module's invoices/payments/receipts are keyed by student. So the
fees of an applicant are a small applicant-level record that reuses the Fees module's money rules and receipt
series (no separate numbering, no payment gateway):

- `branches/{b}/admissionFees/{enquiryId}__{CATEGORY}` — CATEGORY is APPLICATION | REGISTRATION | ADMISSION | CONFIRMATION
  (one per enquiry and category, so setting a fee twice is idempotent). Fields: `amountMinor`, `waivedMinor`,
  `paidMinor`, `refundedMinor`, `currency` (the school's), optional `feeStructureId` (an ACTIVE fee structure with
  category ADMISSION; its amount is the default), `dueDate`, `note`, `status` (DUE | PARTIAL | PAID | WAIVED |
  CANCELLED, derived), `lastReceiptNumber`, `revision`.
- `branches/{b}/admissionFeePayments/{enquiryId}__{requestId}` — append-only: `kind` PAYMENT (with `receiptNumber`
  `RCT-{startYear}-{seq}` and `numberSeq`) or REFUND (no receipt), method, reference, `paymentDate`, `recordedBy`.
- Receipt numbers come from `feeCounters/receipt_{academicYearId}` and are reserved in `receiptNumbers/{number}`
  in the same transaction (the exact shape the Fees module writes, plus `source: 'ADMISSION'`), so a number is
  never issued twice across the two.
- Index: `admissionFeePayments` (enquiryId, recordedAt desc).
- At conversion (phase 8) the net paid amounts are carried into the new student's fee records.
