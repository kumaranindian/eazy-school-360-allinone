import '../../staff/domain/staff_status.dart';
import 'attendance_date.dart';

/// Which staff are on the attendance register for a date. Nobody is marked
/// automatically: this only decides who *appears*.
abstract final class StaffEligibility {
  /// Joined on or before the date, and either currently working
  /// (ACTIVE / ON_NOTICE) or left only after the date (their last status
  /// change is later than the date, so history stays editable for the days
  /// they were employed). INACTIVE/RESIGNED/TERMINATED/RETIRED staff
  /// disappear from the register from their status-change date onwards.
  static bool isEligible({
    required StaffStatus status,
    required DateTime joiningDate,
    required DateTime? statusChangeDate,
    required DateTime date,
  }) {
    final day = AttendanceDate.dateOnly(date);
    if (day.isBefore(AttendanceDate.dateOnly(joiningDate))) return false;
    if (status == StaffStatus.active || status == StaffStatus.onNotice) {
      return true;
    }
    if (statusChangeDate == null) return false;
    return day.isBefore(AttendanceDate.dateOnly(statusChangeDate));
  }
}
