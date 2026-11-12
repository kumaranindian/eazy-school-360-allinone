# API (Cloud Function callables)

All are `onCall`, sign-in required, `callOptions()` (App Check when enabled). They return the
result object or throw an `HttpsError` whose `details.cause` carries the reason.

| Callable | Who | Input | Result |
|---|---|---|---|
| `saveAdmissionSettings` | school admin of the school | `{schoolId, settings, baseVersion?}` | `{version}` |
| `createAdmissionEnquiry` | school admin; branch admin of `branchId` | `{schoolId, branchId, enquiry, assignedTo?}` | `{id, enquiryNumber, duplicateOf[]}` |
| `updateAdmissionEnquiry` | same | `{schoolId, branchId, enquiryId, enquiry, baseRevision?}` | `{revision}` |
| `assignAdmissionEnquiry` | same | `{schoolId, branchId, enquiryId, assignedTo|null}` | `{revision}` |
| `changeAdmissionEnquiryStatus` | same | `{schoolId, branchId, enquiryId, status|"RESUME", reason?, baseRevision?}` | `{status, revision}` |

| `scheduleAdmissionActivity` | same | `{schoolId, branchId, enquiryId, activity{type,scheduledDate,scheduledTime?,remarks?,assignedTo?}, requestId?}` | `{id, duplicate}` |
| `scheduleAdmissionVisit` | same | `{schoolId, branchId, enquiryId, visit{purpose,scheduledDate,scheduledTime?,remarks?,assignedTo?}, requestId?}` | `{id, duplicate}` — also moves the enquiry to VISIT_SCHEDULED |
| `rescheduleAdmissionActivity` | same | `{…, activityId, scheduledDate, scheduledTime?, reason?, baseRevision?}` | `{revision}` |
| `reassignAdmissionActivity` | same | `{…, activityId, assignedTo|null, baseRevision?}` | `{revision}` |
| `completeAdmissionActivity` | same | `{…, activityId, completion{outcome,parentFeedback?,remarks?}, next?{type,scheduledDate,…}, baseRevision?}` | `{revision, nextId?}` |
| `cancelAdmissionActivity` | same | `{…, activityId, reason, baseRevision?}` | `{revision}` |

Scheduled job `admissionFollowUpReminders` (hourly): for every school with admissions and reminders on, once its local
time is inside the 3-hour window from `reminderTime`, it notifies the assignee (or the branch administrators when
unassigned) of each open activity due today (DUE) or earlier, up to 30 days back (OVERDUE).

Applications and documents (phase 6) — same caller rule (school admin; branch admin of that branch), module must be on:

| Callable | Input | Result / effect |
|---|---|---|
| `createAdmissionApplication` | `{schoolId, branchId, enquiryId}` | `{id, applicationNumber, duplicate}` — enquiry must be Interested / Visit scheduled / Visit completed |
| `updateAdmissionApplication` | `{…, application{…}, baseRevision?}` | `{revision}` — DRAFT only |
| `submitAdmissionApplication` | `{…, baseRevision?}` | DRAFT → SUBMITTED; enquiry → APPLICATION_SUBMITTED (needs name, date of birth, year, class, a guardian with a mobile) |
| `reviewAdmissionApplication` | `{…, action: START\|COMMENT, comment?}` | START: SUBMITTED → UNDER_REVIEW (enquiry → UNDER_REVIEW); COMMENT: internal note |
| `decideAdmissionApplication` | `{…, decision: APPROVE\|REJECT, comment?}` | **School admin only, or a branch admin when the school allows it.** APPROVE needs every required document VERIFIED; REJECT needs a comment and closes the enquiry and its follow-ups |
| `requestAdmissionDocumentUpload` | `{…, document{type,fileName,contentType,sizeBytes}, requestId?}` | `{id, storagePath}` — records an UPLOADING document (≤5 MB; PDF/JPEG/PNG/WebP; photographs images only; ≤40 per application) |
| `confirmAdmissionDocumentUpload` | `{…, documentId}` | reads the stored object with admin rights; size and content type must equal what was declared **and the first bytes must be the real signature of that format** (PDF/PNG/JPEG/WebP), else the object is deleted and the record ABANDONED |
| `verifyAdmissionDocument` | `{…, documentId, decision: VERIFY\|REJECT, reason?, baseRevision?}` | UPLOADED → VERIFIED / REJECTED (reason required) |
| `removeAdmissionDocument` | `{…, documentId, reason?}` | UPLOADED/VERIFIED/REJECTED → REMOVED (record and stored file kept) |

Scheduled `admissionDocumentCleanup` (daily): an upload still UPLOADING after 24 h is deleted from Storage (if the bytes arrived) and marked ABANDONED.

School visits are activities of type `SCHOOL_VISIT` and **only** `scheduleAdmissionVisit` creates them (the generic call and a "next contact" refuse that type). Rescheduling, reassigning, completing and cancelling use the same callables as other activities; for a visit they also apply the status effects in WORKFLOWS.

Rules: dates cannot be in the past (school time zone); only a SCHEDULED activity can change; a closed enquiry takes no new
follow-ups; completing requires an outcome (3–500 characters); cancelling requires a reason.

Error mapping: `PERMISSION_DENIED` (wrong role/school/branch), `NOT_FOUND`, `INVALID_ARGUMENT`
(validation; `cause` lists fields), `FAILED_PRECONDITION` (module off, illegal transition,
closed enquiry), `ABORTED` (stale `baseRevision`/`baseVersion`).

Ignored from the client: `schoolId`/`branchId` inside `enquiry`, `status`, `enquiryNumber`,
`createdBy`, `revision`. Only the fields listed in DATABASE_DESIGN are read from `enquiry`.

Pure logic (validation, state machine, numbering, duplicate matching) is exported from
`functions/admission.js` and unit-tested with an in-memory Firestore.

## Admission fees (phase 7)
All are callables (`functions/admission_fees.js`), `{schoolId, branchId, enquiryId, category, ...}`:

| Callable | Who | Effect |
|---|---|---|
| `setAdmissionFee` | school/branch admin | create or change the amount (`amountMinor`, or from `feeStructureId`); cannot go below paid + waived; refused once the enquiry is closed/confirmed |
| `recordAdmissionFeePayment` | school/branch admin | one manual payment, `requestId` idempotent, amount ≤ balance, issues an RCT receipt number; reference required for cheque/bank/UPI/card |
| `waiveAdmissionFee` | school admin | waives the remaining balance (reason required) |
| `refundAdmissionFee` | school admin | refund of money held (reason, `requestId` idempotent); allowed after the enquiry closes |
| `cancelAdmissionFee` | school/branch admin | only when no money is held |
