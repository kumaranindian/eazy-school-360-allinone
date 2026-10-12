import 'attendance_status.dart';

/// Counts of statuses over some set of entries (a class on a day, a student
/// over a month, ...), and the attendance percentage derived from them.
class AttendanceTally {
  final int present;
  final int absent;
  final int late;
  final int halfDay;
  final int notMarked;

  const AttendanceTally({
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.halfDay = 0,
    this.notMarked = 0,
  });

  factory AttendanceTally.of(Iterable<AttendanceStatus?> statuses) {
    var p = 0, a = 0, l = 0, h = 0, n = 0;
    for (final s in statuses) {
      switch (s) {
        case AttendanceStatus.present:
          p++;
        case AttendanceStatus.absent:
          a++;
        case AttendanceStatus.late:
          l++;
        case AttendanceStatus.halfDay:
          h++;
        case null:
          n++;
      }
    }
    return AttendanceTally(
      present: p,
      absent: a,
      late: l,
      halfDay: h,
      notMarked: n,
    );
  }

  int get marked => present + absent + late + halfDay;
  int get total => marked + notMarked;

  int countOf(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => present,
    AttendanceStatus.absent => absent,
    AttendanceStatus.late => late,
    AttendanceStatus.halfDay => halfDay,
  };

  /// Days (or fractions of days) attended: present 1, late 1, half day 0.5.
  double get attendedDays =>
      present + late + halfDay * AttendanceStatus.halfDay.attendanceWeight;

  /// Attendance percentage over the **marked** days only:
  /// `(present + late + 0.5 × halfDay) ÷ (present + absent + late + halfDay) × 100`.
  /// Unmarked days, weekends and holidays have no record and are not in the
  /// denominator. Null when nothing was marked. One tally covers one
  /// reporting period — never combine periods from different academic years.
  double? get percentage => marked == 0 ? null : attendedDays / marked * 100;

  AttendanceTally operator +(AttendanceTally other) => AttendanceTally(
    present: present + other.present,
    absent: absent + other.absent,
    late: late + other.late,
    halfDay: halfDay + other.halfDay,
    notMarked: notMarked + other.notMarked,
  );
}
