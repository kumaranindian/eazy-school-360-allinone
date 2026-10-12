import '../../academic_setup/domain/holiday.dart';
import '../../academic_setup/domain/holiday_type.dart';
import '../../academic_setup/domain/weekday.dart';
import '../../academic_setup/domain/working_days.dart';
import '../../../core/constants/activation_status.dart';

enum CalendarDayKind {
  /// A configured working weekday with no holiday.
  workingDay,

  /// A normally non-working date turned into a working day by a
  /// `SPECIAL_WORKING_DAY` calendar entry.
  specialWorkingDay,

  /// A weekday the branch has configured as non-working.
  nonWorkingDay,

  /// An active public/school/local/special holiday.
  holiday,
}

/// What the branch calendar says about one date.
class CalendarDayInfo {
  final CalendarDayKind kind;

  /// The holiday or special-working-day entry's name, if one applies.
  final String? entryName;

  const CalendarDayInfo(this.kind, {this.entryName});

  /// Ordinary attendance may be marked without an override.
  bool get isSchoolDay =>
      kind == CalendarDayKind.workingDay ||
      kind == CalendarDayKind.specialWorkingDay;

  /// Marking needs an explicit, authorized override with a reason.
  bool get needsOverride => !isSchoolDay;

  String get description => switch (kind) {
    CalendarDayKind.workingDay => 'Working day',
    CalendarDayKind.specialWorkingDay =>
      'Special working day${entryName == null ? '' : ' ($entryName)'}',
    CalendarDayKind.nonWorkingDay => 'Non-working day',
    CalendarDayKind.holiday =>
      'Holiday${entryName == null ? '' : ': $entryName'}',
  };
}

/// Resolves a date against the **branch's** working-day pattern and the
/// academic year's calendar entries — reusing the Milestone 2 data, with no
/// hard-coded weekend.
///
/// Precedence: an active holiday (public/school/local/special) wins over
/// everything; otherwise an active special-working-day entry makes the date
/// a working day; otherwise the weekday pattern decides.
abstract final class AttendanceCalendar {
  static CalendarDayInfo evaluate({
    required DateTime date,
    required WorkingDays workingDays,
    required Iterable<Holiday> calendarEntries,
  }) {
    final matches = calendarEntries
        .where(
          (h) => h.status == ActivationStatus.active && _sameDay(h.date, date),
        )
        .toList();

    for (final entry in matches) {
      if (entry.type != HolidayType.specialWorkingDay) {
        return CalendarDayInfo(CalendarDayKind.holiday, entryName: entry.name);
      }
    }
    final special = matches
        .where((h) => h.type == HolidayType.specialWorkingDay)
        .firstOrNull;
    if (special != null) {
      return CalendarDayInfo(
        CalendarDayKind.specialWorkingDay,
        entryName: special.name,
      );
    }

    final weekday = Weekday.fromDateTimeWeekday(date.weekday);
    return CalendarDayInfo(
      (workingDays.isWorkingDay[weekday] ?? true)
          ? CalendarDayKind.workingDay
          : CalendarDayKind.nonWorkingDay,
    );
  }

  /// Holiday dates are stored as UTC midnight of the civil date; [date] is a
  /// civil date. Compare year/month/day fields, never instants.
  static bool _sameDay(DateTime holidayDate, DateTime date) {
    final h = holidayDate.toUtc();
    return h.year == date.year && h.month == date.month && h.day == date.day;
  }
}
