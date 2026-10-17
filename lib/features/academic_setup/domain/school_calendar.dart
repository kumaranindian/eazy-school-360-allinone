import '../../../core/constants/activation_status.dart';
import 'holiday.dart';
import 'holiday_rules.dart';
import 'holiday_type.dart';
import 'working_days.dart';

/// What the branch calendar says about one date.
enum SchoolDayKind {
  /// A working weekday with no holiday.
  workingDay,

  /// A normally non-working date turned into a working day by an active
  /// `SPECIAL_WORKING_DAY` entry.
  specialWorkingDay,

  /// Closed by the weekly pattern (a weekly off, or a Saturday the policy
  /// marks as a holiday).
  weeklyOff,

  /// Closed by an active holiday, festival, vacation, ...
  holiday,
}

/// The answer for one date. Everything a screen needs to say *why*.
class SchoolDayInfo {
  final SchoolDayKind kind;

  /// The primary holiday (or special-working-day) entry, if one decides it.
  final Holiday? primary;

  /// Every active entry covering the date, in label order. Nothing is merged
  /// or dropped when holidays overlap.
  final List<Holiday> holidays;

  /// "Sunday" / "2nd Saturday": set when the weekly pattern closes the date,
  /// including when a holiday ALSO falls on it.
  final String? weeklyOffLabel;

  const SchoolDayInfo({
    required this.kind,
    this.primary,
    this.holidays = const [],
    this.weeklyOffLabel,
  });

  bool get isWorkingDay =>
      kind == SchoolDayKind.workingDay ||
      kind == SchoolDayKind.specialWorkingDay;

  bool get isWeeklyOff => weeklyOffLabel != null;
  bool get isHoliday => kind == SchoolDayKind.holiday;

  /// The holiday type that applies, if any.
  HolidayType? get holidayType => primary?.type;

  /// The holiday's name when a holiday decides the date.
  String? get holidayName => isHoliday ? primary?.name : null;

  /// One line for banners and skipped-day lists.
  String get description => switch (kind) {
    SchoolDayKind.workingDay => 'Working day',
    SchoolDayKind.specialWorkingDay =>
      'Special working day${primary == null ? '' : ' (${primary!.name})'}',
    SchoolDayKind.weeklyOff => 'Weekly off ($weeklyOffLabel)',
    SchoolDayKind.holiday =>
      'Holiday${primary == null ? '' : ': ${primary!.name}'}',
  };
}

/// The one place that decides whether a date is a school day. Attendance,
/// leave counting, the timetable and the calendar views all ask this — nothing
/// else computes weekly offs or holidays.
///
/// **Precedence** (documented, deterministic):
/// 1. An active holiday / festival / vacation (anything but a special working
///    day) closes the date. If several overlap, the label comes from the
///    lowest [HolidayType.precedence], then the earlier start, then the name;
///    all of them stay in [SchoolDayInfo.holidays].
/// 2. Otherwise an active special working day opens it, even on a weekly off.
/// 3. Otherwise the weekly pattern in force on that date decides.
///
/// **Dates are civil dates.** Only the year, month and day of the [DateTime]
/// given are used; no time zone conversion happens, so a holiday can not slip
/// a day because the device is UTC+5:30 or UTC-8. Stored holiday dates are UTC
/// midnight of their civil date and are compared by year/month/day numbers.
abstract final class SchoolCalendar {
  static SchoolDayInfo evaluate({
    required DateTime date,
    required WorkingDays workingDays,
    required Iterable<Holiday> holidays,
  }) {
    final covering =
        holidays
            .where((h) => h.status == ActivationStatus.active && h.covers(date))
            .toList()
          ..sort(HolidayRules.compareForLabel);
    final off = workingDays.weeklyOffLabel(date);
    final closing = covering.where((h) => h.type.closesSchool).toList();
    if (closing.isNotEmpty) {
      return SchoolDayInfo(
        kind: SchoolDayKind.holiday,
        primary: closing.first,
        holidays: covering,
        weeklyOffLabel: off,
      );
    }
    final special = covering
        .where((h) => h.type == HolidayType.specialWorkingDay)
        .firstOrNull;
    if (special != null) {
      return SchoolDayInfo(
        kind: SchoolDayKind.specialWorkingDay,
        primary: special,
        holidays: covering,
        weeklyOffLabel: off,
      );
    }
    return SchoolDayInfo(
      kind: off == null ? SchoolDayKind.workingDay : SchoolDayKind.weeklyOff,
      holidays: covering,
      weeklyOffLabel: off,
    );
  }
}
