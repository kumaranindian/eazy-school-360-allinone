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

## Indexes (`firestore.indexes.json`)
`admissionEnquiries`: `(assignedTo|status|interestedClassId|academicYearId|source, createdAt desc)`;
`admissionStatusHistory`: `(enquiryId, revision)`. Name search uses `studentNameLower`
(single-field). Phone and number search use equality. The list sends **one** equality filter to
Firestore and applies the others in memory, so the index set stays small.

## Account deletion
`admissionEnquiries`, `admissionStatusHistory` are scanned for uid fields (token replacement);
`admissionSettings` likewise. Prospective-family data is a school record and is kept (matrix D8/D9).
