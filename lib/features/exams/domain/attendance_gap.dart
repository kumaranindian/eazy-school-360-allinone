/// Attendance is read per student when results are finalised. A read that
/// fails must not silently turn into "no attendance on the report card".
class AttendanceGap {
  const AttendanceGap._();

  /// The warning to show before finalising, or null when every student's
  /// attendance was read.
  static String? warning({required int failed, required int total}) {
    if (failed <= 0) return null;
    final who = failed == total
        ? 'all $total students'
        : '$failed of $total students';
    return 'Attendance could not be read for $who. Their report cards would '
        'show no attendance, and finalised results cannot be edited. Cancel '
        'and try again, or finalise without it.';
  }
}
