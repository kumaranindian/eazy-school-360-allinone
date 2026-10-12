import '../../academic_setup/domain/holiday.dart';
import '../../academic_setup/domain/working_days.dart';
import '../../attendance/domain/attendance_calendar.dart';
import '../../attendance/domain/attendance_date.dart';
import 'leave_enums.dart';
import 'leave_type.dart';
import 'leave_units.dart';

/// The outcome of counting an application's days.
class LeaveDaySpan {
  /// Date keys that count as leave (school days, or every day for types that
  /// count non-working days).
  final List<String> countedDateKeys;

  /// Skipped dates and why ("Holiday: Diwali", "Non-working day").
  final Map<String, String> skipped;
  final int units;
  final String? error;

  const LeaveDaySpan({
    required this.countedDateKeys,
    required this.skipped,
    required this.units,
    this.error,
  });

  const LeaveDaySpan.invalid(this.error)
    : countedDateKeys = const [],
      skipped = const {},
      units = 0;

  bool get isValid => error == null;
}

/// The single place leave days are counted — screens, repositories, reports
/// and the staff balance all use this, so a "day" means one thing.
///
/// Dates are civil `yyyy-MM-dd` keys (never instants), so a date cannot shift
/// across a timezone. A day counts when the **branch calendar** (the M2
/// working-days pattern and holiday entries, via the same
/// [AttendanceCalendar] attendance uses) says it is a school day. A type with
/// `countNonWorkingDays` counts every calendar day instead.
abstract final class LeaveDayCalculator {
  static LeaveDaySpan compute({
    required String startKey,
    required String endKey,
    required HalfDay halfDay,
    required LeaveType type,
    required WorkingDays workingDays,
    required Iterable<Holiday> calendarEntries,
    required String yearStartKey,
    required String yearEndKey,
  }) {
    if (!AttendanceDate.keyPattern.hasMatch(startKey) ||
        !AttendanceDate.keyPattern.hasMatch(endKey)) {
      return const LeaveDaySpan.invalid('Choose the start and end dates.');
    }
    if (endKey.compareTo(startKey) < 0) {
      return const LeaveDaySpan.invalid(
        'The end date cannot be before the start date.',
      );
    }
    if (startKey.compareTo(yearStartKey) < 0 ||
        endKey.compareTo(yearEndKey) > 0) {
      return const LeaveDaySpan.invalid(
        'Leave must fall inside the academic year.',
      );
    }
    final keys = AttendanceDate.keysBetween(startKey, endKey);
    if (keys.length > type.effectiveMaxDays) {
      return LeaveDaySpan.invalid(
        'This leave type allows at most ${type.effectiveMaxDays} days in one application.',
      );
    }
    if (halfDay != HalfDay.none) {
      if (!type.allowHalfDay) {
        return const LeaveDaySpan.invalid(
          'Half-day leave is not allowed for this leave type.',
        );
      }
      if (startKey != endKey) {
        return const LeaveDaySpan.invalid(
          'A half day applies to a single date.',
        );
      }
    }

    final counted = <String>[];
    final skipped = <String, String>{};
    for (final key in keys) {
      final info = AttendanceCalendar.evaluate(
        date: AttendanceDate.parse(key),
        workingDays: workingDays,
        calendarEntries: calendarEntries,
      );
      if (type.countNonWorkingDays || info.isSchoolDay) {
        counted.add(key);
      } else {
        skipped[key] = info.description;
      }
    }
    if (counted.isEmpty) {
      return LeaveDaySpan(
        countedDateKeys: const [],
        skipped: skipped,
        units: 0,
        error:
            'No school day falls in this range, so there is nothing to apply for.',
      );
    }
    final units = halfDay == HalfDay.none
        ? counted.length * LeaveUnits.perDay
        : 1;
    return LeaveDaySpan(
      countedDateKeys: counted,
      skipped: skipped,
      units: units,
    );
  }

  /// The day-lock ids a span needs. A full day takes both half-slots, a half
  /// day only its own, so two halves of one date can coexist but a half and a
  /// full day cannot.
  static List<String> lockIds({
    required LeaveKind kind,
    required String subjectId,
    required List<String> dateKeys,
    required HalfDay halfDay,
  }) {
    final slots = switch (halfDay) {
      HalfDay.none => const ['FIRST', 'SECOND'],
      HalfDay.first => const ['FIRST'],
      HalfDay.second => const ['SECOND'],
    };
    return [
      for (final d in dateKeys)
        for (final s in slots) '${kind.wireValue}_${subjectId}__${d}__$s',
    ];
  }
}
