import '../../staff/domain/staff.dart';
import '../../students/domain/student.dart';
import 'attendance_day.dart';
import 'attendance_sheet.dart';
import 'staff_attendance.dart';
import 'student_attendance.dart';

/// A student on a class register for a date.
class EnrolledStudent {
  final Student student;
  final String academicRecordId;

  const EnrolledStudent({
    required this.student,
    required this.academicRecordId,
  });
}

/// Everything needed to show one class's register: who is on it, what is
/// already stored, and the day's DRAFT/FINALIZED state.
class StudentRegister {
  final List<EnrolledStudent> roster;
  final Map<String, StudentAttendance> records;
  final AttendanceDay? day;

  /// Students with a stored record who are *not* on the roster for this date
  /// (e.g. withdrawn that same day). They are appended to the sheet so stored
  /// attendance is never hidden.
  final List<Student> recordOnly;

  const StudentRegister({
    required this.roster,
    required this.records,
    required this.day,
    this.recordOnly = const [],
  });

  /// Roster order is kept, then the record-only students.
  AttendanceSheet toSheet() {
    AttendanceEntry entryFor(Student s, String recordId) {
      final stored = records[s.studentId];
      return AttendanceEntry(
        subjectId: s.studentId,
        name: s.displayName,
        detail: s.rollNumberLabel,
        academicRecordId: stored?.academicRecordId ?? recordId,
        savedStatus: stored?.status,
        savedRemarks: stored?.remarks,
        savedRevision: stored?.revision ?? 0,
        savedSectionId: stored?.sectionId,
      );
    }

    return AttendanceSheet(
      entries: [
        for (final e in roster) entryFor(e.student, e.academicRecordId),
        for (final s in recordOnly)
          entryFor(s, records[s.studentId]?.academicRecordId ?? ''),
      ],
      savedDayStatus: day?.status,
    );
  }
}

/// A staff member on the branch register for a date.
class StaffRegister {
  final List<Staff> roster;
  final Map<String, StaffAttendance> records;
  final AttendanceDay? day;

  const StaffRegister({
    required this.roster,
    required this.records,
    required this.day,
  });

  AttendanceSheet toSheet() {
    return AttendanceSheet(
      entries: [
        for (final s in roster)
          AttendanceEntry(
            subjectId: s.staffId,
            name: s.displayName,
            detail: s.employeeCode,
            savedStatus: records[s.staffId]?.status,
            savedRemarks: records[s.staffId]?.remarks,
            savedRevision: records[s.staffId]?.revision ?? 0,
          ),
      ],
      savedDayStatus: day?.status,
    );
  }
}

/// A query result that may have been cut off at a safety limit.
class AttendanceRange<T> {
  final List<T> items;
  final bool truncated;

  const AttendanceRange(this.items, {this.truncated = false});
}
