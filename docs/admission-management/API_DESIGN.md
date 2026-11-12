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

Error mapping: `PERMISSION_DENIED` (wrong role/school/branch), `NOT_FOUND`, `INVALID_ARGUMENT`
(validation; `cause` lists fields), `FAILED_PRECONDITION` (module off, illegal transition,
closed enquiry), `ABORTED` (stale `baseRevision`/`baseVersion`).

Ignored from the client: `schoolId`/`branchId` inside `enquiry`, `status`, `enquiryNumber`,
`createdBy`, `revision`. Only the fields listed in DATABASE_DESIGN are read from `enquiry`.

Pure logic (validation, state machine, numbering, duplicate matching) is exported from
`functions/admission.js` and unit-tested with an in-memory Firestore.
