# Milestone 11 — Notifications & Parent–Teacher Communication

Status: **implemented, with documented gaps** (push/FCM is *not* implemented).
Milestone 12 has not been started.

## 1. What exists (and what reuses what)

No second notification system was added. Everything extends the mechanisms from
earlier milestones:

| Source | Mechanism (existing) | Read state |
| --- | --- | --- |
| Leave, timetable/substitution, homework returned/graded, **new message** | targeted `notifications` docs (`audience: USER`, `recipientUserId`) | the document's own `readAt` |
| Leave submitted (reviewers) | `notifications` with `audience: REVIEWERS` | `users/{uid}/noticeReads/state` ids |
| Announcements, homework published/due changed, results published | `broadcastNotices` (audience resolved on read, M9) | `users/{uid}/noticeReads/state` ids (≤ 500) |

New in M11: the **notification centre** (`/notifications`), **preferences**
(`/notifications/preferences`), the app-bar **bell**, and **parent–teacher
conversations** (`/messages`, `/messages/new`, `/messages/:id`).

## 2. Notification centre

* Merges the user's own notifications (one bounded listener per branch, newest
  first) with the audience notices addressed to them and reviewers' notices.
* Unread count, All/Unread filter, category filter, “Load earlier” (limit grows
  by 30), mark one read (on open), mark all read (confirmed; only the signed-in
  user's own documents are written, plus their own read list).
* Preference-filtered and expiry-filtered **at display time**.
* The bell badge counts the user's *own* targeted notifications (newest 30 per
  branch, “9+”), minus muted categories. Audience notices are not counted in the
  bell (no per-user document; counting would read the whole notice set from
  every screen). The centre lists and counts both. This difference is by design.
* **Navigation never trusts the stored target.** `NotificationNavigator` maps a
  type to a normal app route; the route's permission check and the page's own
  rules-checked reads decide access. A removed or inaccessible record shows the
  screen's “not available” message (tested).

## 3. Event generation, recipients, idempotency, delivery semantics

* Events are written **in the same atomic commit** as the business change by the
  module that owns it (leave, timetable, homework, announcements, exams — M7–M10
  unchanged), or, for messages, with the message itself.
* Recipients are resolved from trusted relationships at write time (leave
  applicant/reviewers, linked parents, assignment slots, conversation
  `participants`) — never from client-supplied recipient lists. The rules require
  `recipientUserId ∈ participants` and `≠ sender` for message notices.
* **Idempotency:** deterministic ids (`msg__{messageId}`, `{conversationId}__{revision}`
  events, existing M7–M10 ids). A retry re-writes the same document ids and is
  refused as a duplicate (create-only) — it cannot produce a second notice.
  Notices exist only for committed records: drafts produce none.
* **Delivery semantics:** *at-most-once creation per event id, atomic with the
  business change.* There is no exactly-once claim: a client may crash after a
  commit and before it shows confirmation; the retry is harmless.
* **Sensitive previews:** notices carry a title and a short line (“New message
  from Meera Iyer”) — never message text, marks, leave reasons or student work.
* Not wired (would modify finished modules / need a scheduled backend):
  attendance-absence, fee reminder and payment-receipt notices.

## 4. Preferences

`users/{uid}/preferences/notifications`: `mutedCategories` (announcement,
homework, results, attendance, leave, fees, timetable, messages) and
`pushEnabled == false`. Administrative notices are not mutable (UI disables the
switch; rules reject the value; a tampered stored value is ignored on load).
Preferences are the user's own document only. They decide what the centre shows
and counts; events are still recorded.

Channels: **in-app: on. Push: not available. Email/SMS: not provided.** The UI
says so and offers no dead switches.

## 5. Push / FCM — incomplete (reported, not faked)

Delivering push requires (a) the `firebase_messaging` dependency and platform
setup, (b) token registration/rotation, and (c) a trusted sender (Cloud
Function / server using a service account). This project has no Cloud Functions
or server, and **service-account keys must never be in the client**. Therefore
push is not implemented; no tokens are collected; `pushEnabled` is stored
`false`. Documented manual setup is in §12.

## 6. Parent–teacher conversations

Data (branch-scoped):

* `conversations/{cv_…}` — `participants == [parentUserId, teacherUserId]`,
  student, class/section/subject, title, `status` (OPEN/CLOSED/ARCHIVED),
  `revision`, `messageCount`, `lastMessageId/At`, per-member unread counters,
  `flagged` + reporter.
* `conversations/{id}/messages/{m_…}` — create-only (no edit, no delete).
* `conversationEvents/{id}__{revision}` — append-only status/report audit.
* `messageContacts/{staffId}` — teacher opt-in and where they teach.

Rules (enforced in Firestore, not only the UI):

* Only a **linked, ACTIVE, portal-enabled parent** of an **ACTIVE, placed**
  child can open a conversation, and only with a **teacher who holds the
  assignment slot** (subject or class teacher) for that child's section, whose
  staff record is ACTIVE and who has opted in. One conversation is bound to one
  child — children are never mixed.
* Only the two participants read or post. **Administrators cannot read a
  conversation** until a member *reports* it (auditable event); then branch/school
  admins of that tenant may read it and its messages — not its attachments.
* Messages: 1–2000 chars, not whitespace-only, ≤ 3 attachments, `senderUserId ==
  auth.uid`, same commit as the counter bump and (for the recipient) the notice.
* No edit/delete of messages, ever (moderation = report + close; real removal
  needs a trusted backend and would itself need an audit design).
* Status: either member closes; only the teacher (or an administrator) reopens or
  archives (from CLOSED); a closed/archived conversation takes no messages; every
  change writes a `revision + 1` event.
* Unread counters: a message must raise the **other** member's counter by
  exactly one; a reader clears only their own.
* Attachments: Storage path `conversations/{id}/files/{name}` — readable by
  participants, create-only while OPEN, PDF/JPEG/PNG/TXT/DOCX under 10 MB.
* UI safeguards: composer keeps text on failure, a retry re-uses the message id
  (one message), confirmation for close/archive, report dialog with reason,
  history of events.

## 7. Tenant security

Verified by direct emulator reads/writes: other school, other branch, finance,
non-participating teachers/parents, administrators before a report, withdrawn
child, ended link, teacher without slot, teacher who has not opted in.
Storage rules mirror the participant/OPEN checks.

## 8. Performance and consistency

* Bounded listeners: one per branch for notifications (shared by bell and
  centre), one per branch for conversations; thread messages limited (30, “load
  earlier”).
* Unread counters on conversations are maintained in the same commit as the
  message (atomic with it); notification unread counts are aggregate `count()`
  queries on `readAt == null` (billed per query; used for mark-all batches).
* Shared read list is capped at 500 ids (oldest drop off).
* Riverpod: failed loads are not silently retried in the background (`noRetry`),
  and `firestoreProvider` does not retry (no leaked timers).

## 9. Retention

Notifications and conversations are not auto-deleted (no backend). Expiry is a
display filter (`expiresAt`). A scheduled cleanup/retention policy needs a
trusted backend; documented, not implemented.

## 10. Tests (actual)

* Flutter: **863 passed** (817 before; +46): 17 domain/rules/preferences/navigation,
  1 contract export, 27 widget tests, 1 permission test.
* Rules (emulator, serial): **263 passed** (248 before; +15): 12 conversation/
  notification/preference tests, 2 Storage, 1 contract replay of the Dart write
  plans.
* Mutation check of the new rules: **28 mutants, 24 killed, 4 equivalent**
  (message-create checks for status/sender/membership are duplicated by the
  conversation update rule, and `parentUserId == auth.uid` is implied by
  membership + message sender; kept as defence in depth). The check found five
  real test gaps (impersonated parent, spoofed reporter, counter without message,
  non-deterministic notice id, pre-read notice, skipped counter bump) — all fixed.

## 11. Bugs found and fixed during the milestone

* Rules threw “evaluation error” for message paths built by string-joining a
  `/` into a path variable → explicit `convMessagePath`.
* Whitespace-only bodies passed size checks → `matches('(?s).*\\S.*')`.
* Test helper silently ignored unknown override keys (denial cases passed for
  the wrong reason) → named denials and explicit override handling.
* The app-bar bell caused 295 pre-existing widget tests to fail on pending retry
  timers (Riverpod 3 auto-retry on `FirebaseFirestore.instance` throwing without
  an app) → no-retry on the Firebase singleton and the notification providers.

## 12. Known issues and manual setup

* Push notifications are not implemented (see §5). To add: `firebase_messaging`,
  APNs/FCM keys, a token store with per-device docs and rotation, and a Cloud
  Function that sends on `notifications` creates using Admin credentials.
* Attendance/fee/payment notices not wired (needs touching those modules or a
  scheduler).
* First message of a conversation cannot carry an attachment.
* Administrators cannot read attachments of reported conversations (Storage
  rules allow two lookups).
* Preferences filter display only; counts per bell exclude audience notices.
* **Deploy:** `firebase deploy --only firestore:rules,firestore:indexes,storage`
  and wait for indexes (2 new: `conversations`, `messageContacts`). Teachers
  must switch on *Parent messages* in `/messages` before parents can find them.
* iOS build is blocked in this environment (iOS 26.5 platform not installed).
