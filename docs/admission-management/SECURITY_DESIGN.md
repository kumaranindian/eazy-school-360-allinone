# Security design

**Rule 1 — no client writes.** `firestore.rules` has read rules only for the three admission
collections; there is no `allow write`. Every mutation goes through a callable that re-checks the
caller on the server (`assertAdmin`: active user of that school, signed in by an allowed method;
school admin, or branch admin of that branch — home role or `branchRoles`).

**Rule 2 — tenant from the path, not the payload.** The enquiry document is addressed as
`schools/{schoolId}/branches/{branchId}/...` and the caller is authorised for exactly that pair.
Ids are validated (`^[A-Za-z0-9_-]{1,128}$`). A school admin of school B gets `PERMISSION_DENIED`
for school A; a branch admin of branch 1 gets it for branch 2 (both tested).

**Rule 3 — the server owns identity.** Number, status, revision, audit fields and the tenant
fields are set by the function. Sending them is harmless (ignored, tested).

**Reads.** School admin, platform admin (support), branch admin of the same branch. Not teacher,
finance, parent, another school, or signed-out users (rules tests).

**Integrity.** Status changes and history are written in one transaction; history ids include the
revision; `baseRevision` makes concurrent edits fail instead of overwriting.

**Follow-ups.** The same rules as enquiries: read-only to clients (activities and history), every change a callable that re-checks the caller and the tenant path; an activity can only be changed through the enquiry it belongs to; the client cannot set status, assignee identity checks (the assignee must be an active member of the branch), school or branch. Reminder text carries no personal data (enquiry number and kind of contact). Idempotent writes: a client key for scheduling and `create()` with derived ids for notifications.

**Documents and Storage.** `storage.rules` (`admissionDocs`): read by the school admin, the branch admin of **that** branch, and a platform admin (support) — never teachers, finance, parents, other branches, other schools, or signed-out users. Writes are **create-only** and only against an upload the server approved: `admissionDocuments/{docId}` must exist in status UPLOADING for that enquiry, name exactly this path, and declare exactly this size and content type (the callable already validated type, MIME and ≤ 5 MB; the rule re-checks the same). Nothing is ever replaced or deleted from a client. The app reads files through the authenticated Storage SDK (`getData`), **never `getDownloadURL`**, so no forwardable link exists. The server confirms every upload against what is actually stored before it counts (size, content type **and file signature** — the content type is only what the uploader wrote in the metadata), and a daily job removes unconfirmed uploads. Documents are personal data of children: they are listed in the account-deletion matrix as records of the school, not of a user.

**Decisions.** Only a school administrator (or, when the school switches it on, the branch administrator of that branch) can approve or reject; approval is refused until every required document is VERIFIED; verification is a server action that records who and when. Application history is append-only and the application id is the enquiry id, so an application cannot be duplicated or moved to another enquiry.

**Abuse.** Creation is limited to administrators, so there is no public spam surface yet. The
public form (Phase 9) needs a verified school identifier, rate limiting and CAPTCHA before it is
built.

**Privacy.** Internal remarks are never shown outside the staff UI; the parent role has no access.
Callables log ids, not names or phone numbers. Account-deletion handling: DATABASE_DESIGN.

**Known gaps.** Platform admin cannot write (by design for now). Branch admin whose *home* role is
not branch admin but who holds a per-branch admin role can use the callables but not read the
school-wide settings document (rules check the home role there). No documents/Storage yet.

## Admission fees (phase 7)
- `admissionFees` and `admissionFeePayments` are read-only for clients (school admin, platform admin, branch admin of
  the branch); every write is a callable. Rules tests: read scope and denied writes (including FINANCE) in
  `firestore-tests/admission-rules.test.mjs`.
- Nothing is "paid" except by a recorded payment; amounts are positive integer minor units (bounded); payments
  cannot exceed the balance; refunds cannot exceed the money held; waivers and refunds are school-admin only.
- Receipt numbers cannot repeat: the counter and the number reservation are written in the same transaction as the
  payment (tested with concurrent payments).
- Finance staff do not yet see these records (they would need the confidential enquiry too); a Finance view is part of phase 13.

## Conversion (phase 8)
- `admissionConversions` is read-only for clients like the other admission collections (rules test added). The conversion
  itself is a callable guarded by the approval authority; a teacher, another school's admin or an unapproved branch admin is refused.
- Ids are derived from the enquiry (`s_`, `r_`), so a retry or two concurrent conversions cannot create two students (tested).
- The parents' portal access is added only through `parentAccess` (union of keys), the same index the app maintains; no
  login is created (parents get access through the existing "give login" flow).
- Existing parents are matched by exact mobile; a mismatch of people sharing a mobile is possible, as elsewhere in the app.

## Public enquiry page (phase 9)
Threat model: anonymous internet traffic against a write path into a school's data.
- **Tenant**: only the registered slug selects school and branch; a caller-supplied `schoolId`, `branchId`, `status`, `assignedTo` or `remarks` is ignored (tested).
- **Abuse**: a hidden honeypot field (silent success, nothing stored); per-address (5/hour), per-mobile (3/day) and per-school (300/hour) limits
  and a view limit (60/hour per address); App Check (set `ENFORCE_APP_CHECK=true` once web/Android send tokens: reCAPTCHA v3 on web) and optional
  Cloudflare Turnstile (`TURNSTILE_SECRET_KEY`; when set, every submission needs a valid token). Keep the secret out of source control.
- **Privacy**: addresses and mobiles are only stored as salted hashes in counters (set `PUBLIC_PORTAL_SALT`); the enquiry keeps a hash of the address for
  abuse tracing. Consent is explicit, versioned and timestamped. The reply never reveals duplicates, other enquiries or internal ids.
- **Integrity**: validation is the staff form's validation; the id is derived from `requestId` (create-only); duplicates are flagged for staff, never merged.
- **Not covered here**: the Flutter page cannot render a Turnstile widget (it relies on App Check); a school that sets the Turnstile secret must
  also ship a client that can solve it.
