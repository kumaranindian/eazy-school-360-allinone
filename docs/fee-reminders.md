# Fee reminders (school-configurable)

Parents are reminded about fees in the app (push on Android/iOS, plus the
in-app notification feed on every platform; **web push is not supported**).
Each school sets its own policy in **Settings → Fee reminders**
(`/settings/fee-reminders`, school admin only).

## Policy (`schools/{s}/feeReminderSettings/config`)

```
schoolId, enabled, deliveryTime 'HH:MM' (00:00-21:00), includeAmount, includeInvoiceNumber,
beforeDue: { enabled, offsets: [{ days 0..60, enabled }] }   // 0 = on the due date
afterDue:  { enabled, offsets: [{ days 1..90, enabled }] }
updatedAt (server time), updatedBy (uid)
```

* **Why a separate document, not a field on `schools/{s}`**: the school
  document is client-writable by school admins (`changedOnly` list), so a field
  there could not be validated server-side. This follows the `authSettings`
  precedent: admin-read, **no client writes**; the `updateFeeReminderSettings`
  callable (SCHOOL_ADMIN of that school; school id checked against the caller's
  own profile) validates and writes it. Rules: `feeReminderSettings` in
  `firestore.rules`; tests: `firestore-tests/fee-reminder-settings-rules.test.mjs`.
* The **time zone is not stored**: it is the school's Regional setting
  (`schools/{s}.timezone`, India when absent).
* **No document = defaults** (no migration, nothing is switched off): enabled,
  08:00, 3 days before and on the day, **1, 7 and 15 days after**, no amount and
  no invoice number in the text (the previous behaviour). A stored value that
  fails validation also falls back to the defaults rather than silencing the
  school.
* Limits: at most 10 steps per list, no duplicate days, delivery no later than
  21:00 (the 3-hour retry window must end before midnight).

## Schedule (`feeDueReminders`, hourly; `runFeeDueReminders` in `functions/notify_events.js`)

1. For each school: zone from the school document, policy from the settings
   document (defaults if absent). Skip when disabled or no step is on.
2. Handle the school only while its local time is within 3 hours from its
   delivery time (a missed hourly run is retried; the idempotent create makes a
   repeat harmless).
3. "Today" is the school's calendar date; each step looks for invoices whose
   `dueDateKey` is `today + days` (before) or `today - days` (after). This is
   civil-date arithmetic, so DST and leap years cannot move it.
4. For each invoice (paged collection-group query on `dueDateKey`; only schools
   with a matching step): **re-read the invoice**, and skip it unless it is
   still ISSUED/PARTIALLY_PAID with a balance > 0 and the same due date. The
   amount in the text is this fresh balance.
5. Recipients: the student's ACTIVE, portal-enabled parent links whose login is
   an ACTIVE PARENT of the same school. Two children of one parent are two
   invoices and so two reminders.
6. One failing school or invoice is logged and skipped; the rest continue and
   the run reports `failed`. The next hourly run retries it.

Not reminded: paid, cancelled, void, draft, zero-balance, or no valid due date.
Switching on overdue steps never reaches back: a step matches one exact due
date, so an invoice already past a step's day is not reminded for it.

## Notification identity and lifecycle

* Document id `FEE_DUE__{invoiceId}__{days}__{uid}` (before/on the due date;
  **unchanged from the fixed-policy version, so a rollout repeats nothing**) or
  `FEE_OVERDUE__{invoiceId}__{days}__{uid}`, written with `create()` in
  `schools/{s}/branches/{b}/notifications`. A second run, an overlapping run or
  a retry finds the document and creates nothing. Types: `FEE_DUE_REMINDER`,
  `FEE_OVERDUE_REMINDER`; extra fields `studentId`, `dueDateKey`,
  `reminderOffset` (negative = after the due date).
* The existing `pushNotification` trigger delivers it; delivery state lives in
  `pushDeliveries` (`PROCESSING` → `SENT` / `PARTIAL` / `INCOMPLETE` /
  `SCHEDULED` retry / `FAILED`, redriven by `pushRedrive`). See
  `push-notifications.md`. Nothing is marked sent before the push succeeds.
* Clients cannot create notification documents (rules).

## Text

Before: "Dear Parent, the fee invoice for {student} is due on {date}. Please
complete the payment on time." On the day: "...fee payment for {student} is due
today." Overdue: "...overdue by {n} day(s). Please contact the school office if
payment has already been made." With the toggles on, the invoice number
"(invoice INV-7)" and "Amount:" / "Outstanding amount:" (current balance, in the
school's currency) are added. **The amount appears on the lock screen** when
switched on, which is why it is off by default. The settings page preview uses a
sample student and invoice; the real text uses the actual invoice.

## Logs

Structured, ids and counts only (no names, phone numbers or amounts): school
processing / skipped (disabled), invoice skipped (no longer open), duplicate
prevented, invoice failed, school failed, and the run summary
(`created`, `scanned`, `failed`, `truncated`). No metrics beyond Cloud Logging.

## Tests

* `functions/fee_reminders.test.js` (config validation, calendar/DST, delivery
  window, eligibility, messages, overdue, payment-sync, multi-parent/child,
  concurrency, failure isolation, who may save) and `functions/notify_events.test.js`.
* `firestore-tests/fee-reminder-settings-rules.test.mjs` (rules).
* `test/features/fees/fee_reminder_settings_test.dart`,
  `test/widget/fee_reminder_settings_ui_test.dart` (domain + layout at phone,
  tablet, desktop and 1.5x text, add/duplicate/save/turn-off/permission).

## Deploying

Functions (`feeDueReminders`, new callable `updateFeeReminderSettings`) need
the Blaze plan; **prod is not on Blaze**, so none of this runs there yet.
Order: app → functions → rules (the settings page needs the callable; the
scheduler works without the document). The scheduler's per-school settings read
and the existing `invoices.dueDateKey` collection-group index are the only data
dependencies; no new index is needed.
