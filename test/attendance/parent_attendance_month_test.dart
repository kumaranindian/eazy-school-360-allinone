import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/parent_attendance_month.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance.dart';
import 'package:flutter_test/flutter_test.dart';

StudentAttendance _rec(String dateKey, AttendanceStatus status) =>
    StudentAttendance(
      attendanceId: '${dateKey}_s1',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y1',
      dateKey: dateKey,
      studentId: 's1',
      academicRecordId: 'r1',
      classId: 'c5',
      sectionId: 'sa',
      status: status,
    );

void main() {
  test('tallies the month and computes the percentage over marked days', () {
    final m = ParentAttendanceMonth.of(
      [
        _rec('2026-06-01', AttendanceStatus.present),
        _rec('2026-06-02', AttendanceStatus.present),
        _rec('2026-06-03', AttendanceStatus.late),
        _rec('2026-06-04', AttendanceStatus.halfDay),
        _rec('2026-06-05', AttendanceStatus.absent),
      ],
      year: 2026,
      month: 6,
    );
    expect(m.tally.present, 2);
    expect(m.tally.late, 1);
    expect(m.tally.halfDay, 1);
    expect(m.tally.absent, 1);
    // (2 + 1 + 0.5) / 5
    expect(m.percentage, closeTo(70, 0.001));
    expect(m.statusOn(5), AttendanceStatus.absent);
    expect(m.statusOn(6), isNull);
  });

  test('records outside the month are ignored; an empty month has no %', () {
    final m = ParentAttendanceMonth.of(
      [
        _rec('2026-05-31', AttendanceStatus.present),
        _rec('2026-07-01', AttendanceStatus.absent),
      ],
      year: 2026,
      month: 6,
    );
    expect(m.isEmpty, isTrue);
    expect(m.percentage, isNull);
  });

  test('calendar shape: days in month and Monday-first leading blanks', () {
    // 1 June 2026 is a Monday; 1 February 2026 is a Sunday.
    final june = ParentAttendanceMonth.of(const [], year: 2026, month: 6);
    expect(june.daysInMonth, 30);
    expect(june.leadingBlanks, 0);
    final feb = ParentAttendanceMonth.of(const [], year: 2026, month: 2);
    expect(feb.daysInMonth, 28);
    expect(feb.leadingBlanks, 6);
  });
}
