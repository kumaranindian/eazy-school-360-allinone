import 'attendance_day.dart';
import 'attendance_history_entry.dart';
import 'attendance_registers.dart';
import 'attendance_calendar.dart';
import 'attendance_sheet.dart';
import '../../students/domain/student.dart';
import 'student_attendance.dart';

class SaveStudentRegisterRequest {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String dateKey;
  final List<AttendanceEntry> entries;

  /// Lock the register after saving (needs every entry marked).
  final bool finalize;

  /// Required (by the rules) for any change to an already-finalized register.
  final String? reason;

  /// Revision of the day document the user loaded (0 = none yet).
  final int expectedDayRevision;
  final CalendarDayKind dayKind;
  final String? overrideReason;
  final String actorId;

  const SaveStudentRegisterRequest({
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
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

/// Student attendance. Throws an `AppFailure` (via error_mapper) on failure;
/// a [ConflictFailure] when the stored data changed since it was loaded.
abstract class StudentAttendanceRepository {
  /// The class register for [date]: students enrolled in the section on that
  /// date (from their academic history, not the current-placement cache),
  /// their stored attendance, and the day's state.
  Future<StudentRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required DateTime date,
  });

  /// Writes the changed records, their history entries and the day document
  /// in **one transaction**, after re-reading everything and comparing
  /// revisions. Nothing is written if any entry changed underneath the user.
  Future<void> saveRegister(SaveStudentRegisterRequest request);

  /// Section registers for one date (the dashboard). Optional class/section
  /// narrow it.
  Future<List<AttendanceDay>> fetchSessions({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String dateKey,
    String? classId,
    String? sectionId,
  });

  /// All records of one section in a date range (monthly class view).
  Future<AttendanceRange<StudentAttendance>> fetchSectionRange({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  });

  /// One student's records in a date range (their monthly history).
  Future<AttendanceRange<StudentAttendance>> fetchStudentRange({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String fromKey,
    required String toKey,
  });

  Future<List<AttendanceHistoryEntry>> fetchHistory({
    required String schoolId,
    required String branchId,
    required String attendanceId,
  });

  /// Names for report rows (students fetched by id, 30 per query).
  Future<Map<String, Student>> loadStudents({
    required String schoolId,
    required String branchId,
    required Set<String> studentIds,
  });
}
