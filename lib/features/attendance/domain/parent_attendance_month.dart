import 'attendance_date.dart';
import 'attendance_status.dart';
import 'attendance_tally.dart';
import 'student_attendance.dart';

/// One student's attendance for one calendar month, shaped for a parent: the
/// status per date, the tally and the percentage over the **marked** days
/// (the same rule as [AttendanceTally.percentage]). Pure, so it is tested
/// without Firestore.
class ParentAttendanceMonth {
  final int year;
  final int month;

  /// `yyyy-MM-dd` -> status, only for days with a record.
  final Map<String, AttendanceStatus> byDay;
  final AttendanceTally tally;

  const ParentAttendanceMonth._(this.year, this.month, this.byDay, this.tally);

  factory ParentAttendanceMonth.of(
    Iterable<StudentAttendance> records, {
    required int year,
    required int month,
  }) {
    final from = AttendanceDate.firstOfMonthKey(year, month);
    final to = AttendanceDate.lastOfMonthKey(year, month);
    final byDay = <String, AttendanceStatus>{};
    for (final r in records) {
      // Keys sort chronologically, so a plain string range is the month.
      if (r.dateKey.compareTo(from) < 0 || r.dateKey.compareTo(to) > 0) {
        continue;
      }
      byDay[r.dateKey] = r.status;
    }
    return ParentAttendanceMonth._(
      year,
      month,
      byDay,
      AttendanceTally.of(byDay.values),
    );
  }

  double? get percentage => tally.percentage;
  bool get isEmpty => byDay.isEmpty;

  /// Days in the month (28..31).
  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// Status of day-of-month [day], or null when nothing was recorded (a
  /// weekend, a holiday or a day not marked).
  AttendanceStatus? statusOn(int day) =>
      byDay[AttendanceDate.key(DateTime(year, month, day))];

  /// Leading blank cells for a Monday-first grid (Monday = 0).
  int get leadingBlanks => DateTime(year, month, 1).weekday - 1;
}
