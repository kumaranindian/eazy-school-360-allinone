/// One day's attendance for a student or a staff member. Leave is
/// deliberately NOT a status: a future Leave module will reference
/// attendance days rather than write contradictory "LEAVE" records here.
enum AttendanceStatus {
  present('PRESENT', 'Present', 'P', 1),
  absent('ABSENT', 'Absent', 'A', 0),
  late('LATE', 'Late', 'L', 1),
  halfDay('HALF_DAY', 'Half day', 'H', 0.5);

  final String wireValue;
  final String displayName;
  final String shortLabel;

  /// How much of a day this status counts as attended in the attendance
  /// percentage: present 1, late 1 (the person came), half day 0.5,
  /// absent 0. See [AttendanceTally.percentage].
  final double attendanceWeight;

  const AttendanceStatus(
    this.wireValue,
    this.displayName,
    this.shortLabel,
    this.attendanceWeight,
  );

  static AttendanceStatus fromWireValue(String value) =>
      AttendanceStatus.values.firstWhere((s) => s.wireValue == value);
}

/// DRAFT while still being entered or edited; FINALIZED once locked.
/// Changing a finalized day needs a manager and a written reason.
enum AttendanceDayStatus {
  draft('DRAFT', 'Draft'),
  finalized('FINALIZED', 'Finalized');

  final String wireValue;
  final String displayName;

  const AttendanceDayStatus(this.wireValue, this.displayName);

  static AttendanceDayStatus fromWireValue(String value) =>
      AttendanceDayStatus.values.firstWhere((s) => s.wireValue == value);
}
