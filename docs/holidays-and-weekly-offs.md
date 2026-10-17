# Holidays & weekly offs

Settings -> **Weekly offs** and **Holidays** (`/settings/working-days`,
`/settings/holidays`). Both feed one calendar service; nothing else in the app
computes a weekly off or a holiday.

## Where it lives

The brief suggested `schools/{schoolId}/settings/holidayConfiguration`. The app
already keeps both per **branch** (a school with one branch is identical), so
the existing documents were extended instead of duplicated:

| What | Path |
|---|---|
| Weekly pattern | `schools/{s}/branches/{b}/settings/workingDays` |
| Holidays / vacations | `schools/{s}/branches/{b}/academicYears/{y}/holidays/{id}` |

### `settings/workingDays` (additive; old documents still read correctly)

| Field | Meaning |
|---|---|
| `isWorkingDay` | `{MONDAY..SUNDAY: bool}` - the **current** pattern. `SATURDAY: false` means every Saturday is a holiday. |
| `saturdayOffWeeks` | `[1..5]` - while Saturday works, which Saturdays of the month are holidays. Empty = none. |
| `effectiveFrom` | `yyyy-MM-dd` the current pattern applies from. `null` = always (the first save of a branch). |
| `history` | Up to 12 earlier patterns, oldest first: `{effectiveFrom, isWorkingDay, saturdayOffWeeks}`. |
| `updatedAt/By`, `schoolId`, `branchId` | as before |

Saturday policy is **derived**, never stored, so it cannot contradict the data:
no Saturday holidays (no off-weeks) / every Saturday (`SATURDAY:false`) /
alternate 1st-3rd-5th / alternate 2nd-4th / selected (any other set of weeks).
"Custom weekly off days" is the weekday switches themselves.

### Holiday documents

Existing fields plus optional `endDate` (UTC midnight, on/after `date`, at most
366 days inclusive). A single-day holiday has no `endDate` - which is how every
holiday recorded before ranges reads. Types: `PUBLIC`, `FESTIVAL`, `SCHOOL`,
`VACATION`, `OTHER`, and the older `LOCAL`, `SPECIAL`, `SPECIAL_WORKING_DAY`.
`status` ACTIVE/INACTIVE.

**Remove** = make inactive after a confirmation. Holidays are never deleted
(the rules forbid it), so history is kept and a removed holiday can be restored
by editing it.

## Calculation (`SchoolCalendar`, `academic_setup/domain/school_calendar.dart`)

`AttendanceCalendar.evaluate` (used by attendance, leave counting and the
timetable) is a thin adapter over it.

Precedence, per date:
1. An **active holiday / festival / vacation** closes it. Several overlapping:
   the label is chosen by type (public, festival, school, vacation, local,
   special, other), then earlier start, then name. Every record is kept.
2. Otherwise an active **special working day** opens it, even on a weekly off.
3. Otherwise the **weekly pattern in force on that date** decides.

Saturday occurrence = `(dayOfMonth - 1) ~/ 7 + 1` (1-7 -> 1st ... 29-31 -> 5th),
applied only after checking the date is a Saturday. A 5th-Saturday rule
therefore fires only in months that have one.

**Dates are civil dates** (year/month/day fields; stored holiday dates are UTC
midnight and compared by those numbers). No time-zone conversion happens, so a
device's offset can not move a holiday.

## Effective dating

Saving a change on a configured branch asks "takes effect from" (default
today). The previous pattern moves to `history`; `patternFor(date)` picks the
latest pattern whose `effectiveFrom` is on or before the date. Consequences:

- Dates before the change are judged exactly as before - attendance and leave
  already recorded are not reinterpreted.
- A new pattern may not start before the current one (it would re-date days
  already judged by it). Saving on the same start date corrects it in place.
- The first save of an unconfigured branch applies from the beginning.

## Integrations

- **Attendance:** unchanged flow, now with Saturday patterns and ranges. A
  non-school day shows "Weekly off (2nd Saturday)" / "Holiday: <name>"; only a
  manager can mark it, with a recorded reason. Nothing writes absences for
  holidays; reports do not count days with no record.
- **Leave:** days that are not school days are **not counted** in the duration
  (unless the leave type counts non-working days) and are listed with the
  reason. A request overlapping a holiday is not refused; only a range with no
  school day at all is ("nothing to apply for"). Balances, fees and recorded
  attendance are not touched.
- **Calendar view:** month grid with weekly offs, holidays by type and special
  working days, plus a legend.

## Security (`firestore.rules`)

- `workingDays` and holidays are written only by an admin of that branch
  (school admin / branch admin), nobody else, never across schools; never
  deleted.
- New validation: `validWorkingDays` (all seven weekdays boolean, off-weeks
  1-5, valid `effectiveFrom`, bounded history) and `validHoliday` (name,
  known type, `endDate` on/after `date` and within 366 days inclusive,
  status).
- Read: staff of the branch, and a family with a child in the branch
  (`parentAccess`) for the working days and holidays only.

## Not supported (extension points)

- **Audience per holiday** (students vs staff vs parents): there is one
  calendar per branch. A separate staff calendar would be a second set of
  `settings`/holidays read by the staff attendance screens.
- **Academic-year association of the weekly pattern**: it is per branch with
  effective dates, which covers year changes without a second document.
