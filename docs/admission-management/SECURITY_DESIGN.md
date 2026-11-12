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

**Abuse.** Creation is limited to administrators, so there is no public spam surface yet. The
public form (Phase 9) needs a verified school identifier, rate limiting and CAPTCHA before it is
built.

**Privacy.** Internal remarks are never shown outside the staff UI; the parent role has no access.
Callables log ids, not names or phone numbers. Account-deletion handling: DATABASE_DESIGN.

**Known gaps.** Platform admin cannot write (by design for now). Branch admin whose *home* role is
not branch admin but who holds a per-branch admin role can use the callables but not read the
school-wide settings document (rules check the home role there). No documents/Storage yet.
