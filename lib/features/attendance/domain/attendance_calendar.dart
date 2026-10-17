import '../../academic_setup/domain/holiday.dart';
import '../../academic_setup/domain/school_calendar.dart';
import '../../academic_setup/domain/working_days.dart';

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
    CalendarDayKind.nonWorkingDay =>
      entryName == null ? 'Non-working day' : 'Weekly off ($entryName)',
    CalendarDayKind.holiday =>
      'Holiday${entryName == null ? '' : ': $entryName'}',
  };
}

/// Resolves a date against the **branch's** weekly pattern (Saturday policies
/// and effective dates included) and the academic year's calendar entries.
///
/// This is a thin adapter over [SchoolCalendar], the single implementation of
/// the precedence rules: an active holiday wins over everything; otherwise an
/// active special-working-day entry makes the date a working day; otherwise
/// the weekly pattern in force on that date decides.
abstract final class AttendanceCalendar {
  static CalendarDayInfo evaluate({
    required DateTime date,
    required WorkingDays workingDays,
    required Iterable<Holiday> calendarEntries,
  }) {
    final info = SchoolCalendar.evaluate(
      date: date,
      workingDays: workingDays,
      holidays: calendarEntries,
    );
    return switch (info.kind) {
      SchoolDayKind.holiday => CalendarDayInfo(
        CalendarDayKind.holiday,
        entryName: info.primary?.name,
      ),
      SchoolDayKind.specialWorkingDay => CalendarDayInfo(
        CalendarDayKind.specialWorkingDay,
        entryName: info.primary?.name,
      ),
      SchoolDayKind.weeklyOff => CalendarDayInfo(
        CalendarDayKind.nonWorkingDay,
        entryName: info.weeklyOffLabel,
      ),
      SchoolDayKind.workingDay => const CalendarDayInfo(
        CalendarDayKind.workingDay,
      ),
    };
  }
}
