# Multi-country support: currency, time zone, date format

A school chooses its **country, currency, time zone and date format** once, in
**Settings → Regional settings** (school administrators only). The whole app
follows it. One setting per school: every branch inherits it.

## What is stored
On `schools/{schoolId}`:

| Field | Example | Notes |
|---|---|---|
| `countryCode` | `AE` | ISO 3166-1 alpha-2 |
| `currency` | `AED` | ISO 4217; one of the codes in `lib/core/regional/currency.dart` |
| `timezone` | `Asia/Dubai` | IANA name |
| `dateFormat` | `dd/MM/yyyy` | one of `DateFormats.all` |
| `currencyLocked` | `true` | **server-written only** (see below) |

A school that predates the setting has none of these and behaves exactly as
before: India / INR / `Asia/Kolkata` / `dd/MM/yyyy` (`RegionalSettings.legacy`)
until an admin saves its settings. `firestore.rules` validate the shape
(`validRegional`) and refuse clients writing `currencyLocked`.

## Currency
* Money is still an **integer number of minor units**. What changed is how many
  decimals a minor unit has: 2 for INR/USD/EUR…, **0** for JPY/KRW/VND/UGX/RWF/XOF,
  **3** for KWD/BHD/OMR/JOD. `Money.format / parseMinor / plain` take the
  currency (always explicit - there is no default) and print/parse that many
  decimals. Grouping is lakh/crore for INR/BDT/LKR/NPR/PKR, thousands otherwise.
* The rules only do integer arithmetic on those counts, so they are unaffected.
* **Currency lock.** Changing the currency under existing amounts would leave a
  school with mixed currencies. The first fee structure, invoice or payment makes
  a Cloud Function (`lockCurrencyOnFeeStructure/Invoice/Payment`) set
  `currencyLocked`; from then on the rules refuse a currency change (country,
  time zone and date format stay editable). A school that has money from before
  this existed must be locked once: `node tool/lock_currencies.js` (dry-run
  first). Residual: an admin saving a new currency within seconds of the very
  first fee document being created can win the race; the documents keep their own
  `currency`, so nothing is corrupted, only mixed.
* Invoices and payments store their `currency`; screens show what the document
  says. New documents use the school's currency.

## Time zone
Three kinds of time are kept apart (`lib/core/regional/school_time.dart`):
* **civil dates** (`yyyy-MM-dd` keys, UTC-midnight stamps) say which school day
  something belongs to. "Today" (`SchoolTime.todayKey()`, `FeeDates.todayKey()`,
  default dates in attendance, leave, fees, timetable, homework…) is the
  **school's** day, not the device's: a parent travelling abroad or an admin on a
  laptop in another zone sees the same day as the school.
* **instants** (homework deadline, announcement publish time, audit stamps) are
  real moments. They are *entered* as the school's wall clock
  (`SchoolTime.instantFromWall`, e.g. `Homework.dueInstant`: 17:00 means 17:00
  school time) and *shown* in the school zone (`formatInstant`). Comparisons with
  `DateTime.now()` and with the server's `request.time` stay real-instant.
* `SchoolTime` is set from the signed-in school in `app.dart` and cleared at
  sign-out (until then: device zone, `dd/MM/yyyy`, as before). The navigator is
  re-keyed when the zone/format changes so open screens redraw.
* Zone arithmetic uses the IANA database from the `timezone` package (adds
  ~0.9 MB to the uncompressed web bundle; DST is correct for every year).

## Cloud Functions
* `feeDueReminders` runs **hourly** and handles each school at 08:00 in its
  own zone (retried for three hours; idempotent). Schools with no zone keep the
  Indian schedule.
* Notice texts use an unambiguous "3 Aug 2026" date.

## Rolling it out
1. Deploy the app, then functions, then rules (the rules accept the new fields
   either way, but the app writes them).
2. `node tool/lock_currencies.js` (dry-run, then `--apply`) for schools that
   already hold fees/payments.
3. Existing school admins: Settings → Regional settings shows "Not set up yet"
   with the defaults in use; saving sets them explicitly.

## Not covered (by design, for now)
* One country/currency **per school**; per-branch overrides would need a
  per-branch settings document and care with branch transfers and school-wide
  reports.
* Language / translations, right-to-left layouts, locale-specific number
  formatting beyond grouping, tax/VAT, and a currency converter.
* PDF documents print the currency **code** (the built-in fonts have no
  symbols).
* **Phone numbers.** A national-format mobile saved on a staff/parent record
  (`0501234567`, `4155550123`) is completed with the dialling code of the
  *school's* country (`functions/dial_codes.js`; a leading trunk `0` is dropped).
  At phone sign-in the school is not yet known, so a number typed there should
  include the country code (`+971…`; the field says so); without it the
  deployment default `DEFAULT_PHONE_COUNTRY_CODE` (91) applies. The WhatsApp
  template, language and Meta account are still one per deployment.
