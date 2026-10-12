import 'attendance_calendar.dart';
import 'attendance_day.dart';
import 'attendance_history_entry.dart';
import 'attendance_registers.dart';
import 'attendance_sheet.dart';
import 'staff_attendance.dart';

class SaveStaffRegisterRequest {
  final String schoolId;
  final String branchId;
  final String dateKey;
  final List<AttendanceEntry> entries;
  final bool finalize;
  final String? reason;
  final int expectedDayRevision;
  final CalendarDayKind dayKind;
  final String? overrideReason;
  final String actorId;

  const SaveStaffRegisterRequest({
    required this.schoolId,
    required this.branchId,
    required this.dateKey,
    required this.entries,
    required this.finalize,
    this.reason,
    required this.expectedDayRevision,
    this.dayKind = CalendarDayKind.workingDay,
    this.overrideReason,
    required this.actorId,
  });
}

/// Staff attendance, per branch and date. Same contract as
/// `StudentAttendanceRepository`.
abstract class StaffAttendanceRepository {
  /// Staff on the register for [date] (see `StaffEligibility`), their stored
  /// attendance, and the day's state.
  Future<StaffRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required DateTime date,
  });

  Future<void> saveRegister(SaveStaffRegisterRequest request);

  Future<AttendanceDay?> fetchDay({
    required String schoolId,
    required String branchId,
    required String dateKey,
  });

  /// Records in a date range, optionally for one staff member.
  Future<AttendanceRange<StaffAttendance>> fetchRange({
    required String schoolId,
    required String branchId,
    required String fromKey,
    required String toKey,
    String? staffId,
  });

  Future<List<AttendanceHistoryEntry>> fetchHistory({
    required String schoolId,
    required String branchId,
    required String attendanceId,
  });
}
