import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/academic_setup/domain/calendar_repository.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_day.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_history_entry.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_registers.dart';
import 'package:eazy_school_360/features/attendance/domain/staff_attendance_repository.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance_repository.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';

Student fakeStudent(String id, String first, {String? roll}) => Student(
  studentId: id,
  schoolId: 'school-1',
  branchId: 'main',
  admissionNumber: 'ADM-$id',
  studentCode: 'STU-$id',
  firstName: first,
  lastName: 'Kumar',
  dateOfBirth: DateTime(2015, 4, 10),
  gender: Gender.male,
  admissionDate: DateTime(2026, 6, 1),
  status: StudentStatus.active,
  currentRollNumber: roll,
);

/// Serves a canned register and records every save the UI performs.
class FakeStudentAttendanceRepository implements StudentAttendanceRepository {
  StudentRegister register;
  List<AttendanceDay> sessions;
  final List<SaveStudentRegisterRequest> saves = [];
  int loads = 0;

  /// Awaited inside saveRegister — lets a test hold a save "in flight".
  Future<void> Function()? saveGate;
  Object? saveError;

  FakeStudentAttendanceRepository({
    required this.register,
    this.sessions = const [],
  });

  @override
  Future<StudentRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required DateTime date,
  }) async {
    loads++;
    return register;
  }

  @override
  Future<void> saveRegister(SaveStudentRegisterRequest request) async {
    saves.add(request);
    if (saveGate != null) await saveGate!();
    if (saveError != null) throw saveError!;
  }

  @override
  Future<List<AttendanceDay>> fetchSessions({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String dateKey,
    String? classId,
    String? sectionId,
  }) async => sessions
      .where(
        (d) =>
            (classId == null || d.classId == classId) &&
            (sectionId == null || d.sectionId == sectionId),
      )
      .toList();

  @override
  Future<List<AttendanceHistoryEntry>> fetchHistory({
    required String schoolId,
    required String branchId,
    required String attendanceId,
  }) async => const [];

  List<StudentAttendance> sectionRecords = [];
  final List<Map<String, String>> rangeRequests = [];

  @override
  Future<AttendanceRange<StudentAttendance>> fetchSectionRange({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async {
    rangeRequests.add({'from': fromKey, 'to': toKey, 'section': sectionId});
    return AttendanceRange(sectionRecords);
  }

  @override
  Future<Map<String, Student>> loadStudents({
    required String schoolId,
    required String branchId,
    required Set<String> studentIds,
  }) async => {for (final r in register.roster) r.student.studentId: r.student};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStaffAttendanceRepository implements StaffAttendanceRepository {
  StaffRegister register;
  AttendanceDay? day;
  final List<SaveStaffRegisterRequest> saves = [];

  FakeStaffAttendanceRepository({required this.register, this.day});

  @override
  Future<StaffRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required DateTime date,
  }) async => register;

  @override
  Future<void> saveRegister(SaveStaffRegisterRequest request) async =>
      saves.add(request);

  @override
  Future<AttendanceDay?> fetchDay({
    required String schoolId,
    required String branchId,
    required String dateKey,
  }) async => day;

  @override
  Future<List<AttendanceHistoryEntry>> fetchHistory({
    required String schoolId,
    required String branchId,
    required String attendanceId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCalendarRepository implements CalendarRepository {
  WorkingDays workingDays;
  List<Holiday> holidays;

  /// By default every weekday (including Saturday/Sunday) is a working day,
  /// so tests do not depend on which day of the week they run.
  FakeCalendarRepository({WorkingDays? workingDays, this.holidays = const []})
    : workingDays =
          workingDays ??
          WorkingDays(
            schoolId: 'school-1',
            branchId: 'main',
            isWorkingDay: {
              for (final d in WorkingDays.defaultPattern().keys) d: true,
            },
          );

  @override
  Future<WorkingDays> getWorkingDays(String schoolId, String branchId) async =>
      workingDays;

  @override
  Stream<List<Holiday>> watchHolidays(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(holidays);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StudentAttendance fakeStoredAttendance(
  String studentId, {
  required String dateKey,
  required status,
  int revision = 1,
}) => StudentAttendance(
  attendanceId: StudentAttendance.idFor(dateKey, studentId),
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  dateKey: dateKey,
  studentId: studentId,
  academicRecordId: 'rec-$studentId',
  classId: 'c5',
  sectionId: 'sec-a',
  status: status,
  revision: revision,
);

Staff attendanceStaff(String id, String first) =>
    Staff.fromFirestore('school-1', 'main', id, {
      'employeeCode': 'EMP-$id',
      'firstName': first,
      'lastName': 'Rao',
      'dateOfBirth': _ts(DateTime(1990, 1, 1)),
      'gender': 'FEMALE',
      'phone': '9999999999',
      'joiningDate': _ts(DateTime(2020, 1, 1)),
      'employmentType': 'FULL_TIME',
      'departmentId': 'd',
      'designationId': 'g',
      'status': 'ACTIVE',
      'isTeacher': false,
    });

dynamic _ts(DateTime d) => Timestamp.fromDate(d);
