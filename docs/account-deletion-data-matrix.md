# Account deletion: data handling matrix

Status: **decisions D2-D5 and D7 accepted as recommended; D1 and D6 still pending (records are
retained). Implemented in `functions/deletion_processor.js`, behind the off-by-default flag
`ACCOUNT_DELETION_PROCESSING_ENABLED`.** Built from the
actual schema (Firestore rules, Dart models, Cloud Functions), not from assumptions.

No retention period appears below because none has been decided. Where a record might have to
be kept, the cell says **PENDING** rather than guessing a period or citing a law.

Actions: **DELETE** (removed), **ANONYMIZE** (identifying fields replaced; the rest kept),
**RETAIN** (left as is), **SCHOOL** (the school decides; the processor does not touch it).

## 1. Who is asking, and what that changes

| Requester | Their account | Their school records | School's records about others |
|---|---|---|---|
| Parent | deleted (rows A) | their guardian record: see B1 (decision D2) | never touched (decision 4): children, attendance, results, fees |
| Teacher / finance / branch admin | deleted (rows A) | their staff record and authored content: B2-B10 | never touched |
| School admin (not the only one) | deleted (rows A) | as staff | never touched; the **school is never deleted** |
| School admin (the only one) | held in `ACTION_REQUIRED` until another admin exists | - | - |
| Platform admin | not self-service; handled by Avail404 | - | - |

A user belongs to **one school** (`/users/{uid}.schoolId`); several branches possible. So
"multiple school memberships" cannot occur today, and no other school's data is in scope.

## 2. Matrix

### A. The login account (always removed)

| # | Data | Where | Proposed action | Reason | School admin needed? | Retention |
|---|---|---|---|---|---|---|
| A1 | Sign-in account: email, phone, password hash, Google link | Firebase Authentication | **DELETE** (Admin SDK). Irreversible; also revokes sessions | The account is the core of the request | No | None |
| A2 | Profile: name, email, phone, photo, login settings, `linkedParentId` | `/users/{uid}` | **ANONYMIZE** to a stub: keep the document id, school and role; `status: DISABLED` plus `deleted: true` (a status every screen already understands); clear name, email, phone, photo, login, links | The stub keeps audit references valid without identifying anyone | No | stub kept (opaque) |
| A3 | Push tokens | `/users/{uid}/devices/*` | **DELETE** | Only for delivering that person's notices | No | None |
| A4 | Personal notifications and preferences | `notifications` (audience USER, `recipientUserId`), preferences | **DELETE** | The person's own inbox | No | None |
| A5 | OTP challenge and rate records | `otpChallenges`, `otpRate` | none (hashes only, expire on their own TTL) | Not readable as personal data | No | 24 h TTL |
| A6 | Push delivery records | `pushDeliveries/{eventId}` | verify in Phase 5 that none carries a user id; if so, ANONYMIZE | Delivery bookkeeping | No | PENDING |

### B. School records that name the person (school-owned)

| # | Data | Where | Proposed action | Reason | School admin needed? | Retention |
|---|---|---|---|---|---|---|
| B1 | **Parent/guardian record**: name, phone(s), email, address, occupation, photo | `.../parents/{id}` | **Decision D2.** Proposed: ANONYMIZE contact details and photo, name becomes "Deleted guardian", unlink the login. Keep the record so the child's guardian count and history stay valid | It is the parent's own personal data (decision 4), but the school still needs a guardian link for the child | **Yes, notify**: the school loses this contact | PENDING |
| B2 | **Staff record**: DOB, gender, blood group, phones, address, employee code, joining date, employment type | `.../staff/{id}` | Proposed: unlink login; **DELETE** photo, blood group, alternate phone, address; **RETAIN** employment facts (code, dates, type, department) | Employment facts may be needed for payroll or statutory records; optional personal details are not | **Yes, confirm** | PENDING (HR/statutory) |
| B3 | Staff documents | Storage `staff/{id}/documents/*` and `.../documents` | **SCHOOL**: not deleted automatically | HR documents are the employer's | Yes | PENDING |
| B4 | Leave applications by the person: reason, attachments, name | `leaveApplications`, Storage `leaveDocs/{uid}/*` | **DELETE** attachments and free-text reason (may hold health data); **ANONYMIZE** `applicantName`; **RETAIN** dates, type and decision | Balances and payroll depend on dates and decisions | No | PENDING |
| B5 | Leave decisions made by the person | `decidedBy`, `decidedByName` | **ANONYMIZE** the name | Decision history must stay | No | PENDING |
| B6 | Messages the person wrote (parent-teacher) | `conversations/*/messages` and files | **Decision D3.** Proposed: **ANONYMIZE** sender name, **DELETE** the person's attachments, keep message text so the other person's thread stays intact | Conversation has two owners | No | PENDING |
| B7 | Announcements and notices authored by staff | `announcements`, `broadcastNotices` | **ANONYMIZE** author name; keep content | School communication | No | PENDING |
| B8 | Attendance, marks, timetable and homework entries made by a teacher | `markedBy`, `enteredBy`, names | **ANONYMIZE** names; keep the records | School academic records | No | PENDING |
| B9 | Students: all fields, fees, results, submissions | `students/*` etc. | **Never touched** by anyone's account deletion (decision 4) | School records about children | n/a | School |

### C. Financial records (not deleted merely because they mention someone)

| # | Data | Where | Proposed action | Reason | Retention |
|---|---|---|---|---|---|
| C1 | Payments and receipts: `collectedBy`, `collectorName`, `studentName` | `payments`, `receipts` | **RETAIN unchanged** by default. **Decision D4** whether to pseudonymise `collectorName` | Issued receipts and invoices are accounting records | **PENDING** |
| C2 | Invoices, waivers, reversals, financial audit log (actor uid and name) | `invoices`, `invoiceWaivers`, `paymentReversals`, `financialAuditLogs` | **RETAIN** | Accounting and audit integrity | **PENDING** |

### D. Audit trail

| # | Data | Where | Proposed action | Retention |
|---|---|---|---|---|
| D1 | `createdBy` / `updatedBy` uid on tenant documents | almost every collection | **Decision 5 (yes): replace the uid with a non-identifying token** (a keyed hash, same token per person so history stays consistent, not reversible without the key). Heavy: collection-group scans across dozens of collections with index overrides, paginated and resumable. Until it runs the uid is only an opaque id, because A1 and A2 already remove who it was | PENDING |
| D2 | Security audit events | `schools/*/authAudit` (actor and target ids, no secrets) | same token replacement | PENDING |

### E. Outside our database

| # | Data | Action |
|---|---|---|
| E1 | Firestore point-in-time recovery and backups | **Cannot be edited.** Deleted data persists until the backup window ends. State the window in the privacy policy once PITR is configured |
| E2 | Cloud Logging | Logs hold references and statuses, never emails or tokens. Default log retention applies |
| E3 | Crashlytics | The app sets no user id, so reports are not tied to the account. Device-level reports expire on Google's schedule |
| E4 | Meta WhatsApp (sign-in codes) | Messages were delivered to the person's phone number; Meta's retention is outside our control. Say so in the policy |
| E5 | Deletion request record (reference, status, timestamps, reviewer) | **RETAIN** as proof the request was handled; e-mail already scrubbed at the end of a request. Period **PENDING** |

## 3. How it will run (Phase 5 design, for review)

1. Pre-flight again: still the same account, request `APPROVED`, not a platform admin, not the
   only active school admin, feature flag `ACCOUNT_DELETION_PROCESSING_ENABLED=true`.
2. Order: disable the login and revoke sessions -> A3, A4 -> B (per decisions) -> D1/D2 ->
   A2 stub -> **A1 delete last** -> mark `COMPLETED`.
3. Every step is idempotent, paginated (small batches), checkpointed on the request document,
   safe to retry, and logs counts only. A partial failure leaves `FAILED_RETRYABLE`.
4. Never run against production without your explicit go-ahead; tested on the emulators only.
5. The person is told `COMPLETED` only after all steps finish.

## 4. Honest limits (to reflect in the policy and Data safety form)

- **Pseudonymised, not anonymous.** After A1/A2/D1 the audit tokens identify nobody, but
  denormalised **names inside records** (`collectorName`, `studentName`, `applicantName`,
  `teacherName`, ...) are text and must be handled row by row. Where a record is retained as is
  (C1, C2) a name stays in it. That is a retention choice, not anonymization, and must not be
  described as such.
- Fields I could not enumerate with certainty without Phase 5 scanning: free-text notes and
  reasons elsewhere (for example status-change notes on staff). The processor will report counts
  of what it changed so you can check.
- Backups and PITR (E1) mean "deleted" does not mean "gone from every copy immediately".

## 5. Decisions needed before any destructive step runs

| ID | Question | My recommendation |
|---|---|---|
| D1 | Retention for fee, invoice, payment, receipt and financial-audit records (C1, C2, D2) | Decide with your accountant/counsel. Until then RETAIN and publish no period |
| D2 | Parent record on a parent's request (B1): unlink only, anonymize contact details (proposed), or leave as is | Anonymize contact details and photo, keep the record, notify the school admin |
| D3 | Messages the person wrote (B6): keep text with anonymized sender (proposed), blank the text, or leave | Keep text, anonymize sender, delete their attachments |
| D4 | Pseudonymise `collectorName` on retained receipts (C1) | Leave unchanged until D1 is decided |
| D5 | Staff HR record on a staff request (B2, B3): which employment facts to keep, and who confirms | Keep employment facts, delete optional personal details, school admin confirms |
| D6 | Keep the deletion request record for how long (E5) | Your call; I will not suggest a period |
| D7 | Who at Avail404 is the reviewer, and the backup/PITR window to publish (E1) | Name one `PLATFORM_ADMIN` reviewer; publish the real PITR window |

## 6. Status of the decisions

| ID | Decision | Implemented as |
|---|---|---|
| D1 | Retention of financial records | **PENDING.** Retained unchanged; the processor never touches fee, invoice, payment, receipt or financial-audit collections |
| D2 | Parent record | Recommended: contact details and photo removed, name "Deleted guardian", login unlinked, `parentAccess` removed, record kept |
| D3 | Messages | Recommended: sender name and id replaced, their attachments deleted, text kept |
| D4 | `collectorName` on receipts | Recommended: unchanged (part of D1) |
| D5 | Staff record | Recommended: login unlinked; photo, blood group, alternate phone and address removed; employment facts and HR documents kept |
| D6 | Retention of the deletion-request record | **PENDING.** Kept; no period published |
| D7 | Reviewer and backup window | Recommended: one named PLATFORM_ADMIN reviewer (to be created); backup/PITR window to be published once configured |

## 7. What the processor does not do (read before enabling)

- It does **not notify the school** that a guardian or staff record changed. The request
  records the counts; Avail404 should tell the school administrator (matrix B1, B2 "school admin
  needed"). A school-facing notice is not built.
- Names written **inside free text** (leave `remarks`, status-change notes, message bodies) are not
  searched for or changed. Records that other people wrote *about* the person (an approver's remarks
  on their leave, a teacher's note) stay as the school's records.
- Pseudonymisation tokens come from a keyed hash of the uid. Anyone holding the key can recompute
  the token for a known uid; protect `OTP_PEPPER` (the key is derived from it with a fixed label).
- Backups and point-in-time recovery cannot be edited (E1).
