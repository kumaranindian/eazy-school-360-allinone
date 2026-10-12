import '../../students/domain/student_academic_record.dart';
import '../../students/domain/student_status.dart';
import 'attendance_date.dart';

/// Who is on a class register on a given date, from the student's own
/// academic history — not from the "current placement" cache, so a past
/// date shows the class the student was *actually* in then.
abstract final class EnrollmentEligibility {
  /// A placement covers `[startDate, endDate)` as civil dates: the start day
  /// is included and the end day is not. A transfer on day D ends the old
  /// record on D and starts the new one on D, so on D the student appears
  /// only in the new section — never in both.
  static bool recordCovers(StudentAcademicRecord record, DateTime date) {
    final day = AttendanceDate.dateOnly(date);
    final start = AttendanceDate.dateOnly(record.startDate);
    if (day.isBefore(start)) return false;
    final end = record.endDate;
    if (end == null) return true;
    return day.isBefore(AttendanceDate.dateOnly(end));
  }

  /// Withdrawing/graduating a student changes [Student.status] but does not
  /// close their academic record, so the status change date also bounds
  /// eligibility: before it they were still enrolled, from it onwards not.
  static bool studentStillEnrolled({
    required StudentStatus status,
    required DateTime? statusChangeDate,
    required DateTime date,
  }) {
    if (status == StudentStatus.active) return true;
    if (statusChangeDate == null) return false;
    return AttendanceDate.dateOnly(
      date,
    ).isBefore(AttendanceDate.dateOnly(statusChangeDate));
  }
}
