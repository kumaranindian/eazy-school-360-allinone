import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_repository.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';

Student fakeStudent(
  String id, {
  String first = 'Asha',
  String last = 'Nair',
  String admission = 'ADM-001',
  StudentStatus status = StudentStatus.active,
  String? yearId,
  String? classId,
  String? sectionId,
}) => Student(
  studentId: id,
  schoolId: 'school-1',
  branchId: 'main',
  admissionNumber: admission,
  studentCode: 'S-$id',
  firstName: first,
  lastName: last,
  dateOfBirth: DateTime(2015, 4, 1),
  gender: Gender.female,
  admissionDate: DateTime(2024, 6, 1),
  status: status,
  currentAcademicYearId: yearId,
  currentClassId: classId,
  currentSectionId: sectionId,
);

/// The student roster for list-page tests: browse by status, search by name or
/// admission number, and server-style counts. Everything else is unsupported.
class FakeStudentListRepository implements StudentRepository {
  final List<Student> students;
  final List<StudentStatus?> fetchStatuses = [];
  final List<StudentStatus?> countCalls = [];
  final List<String> nameSearches = [];
  final List<String> admissionSearches = [];

  FakeStudentListRepository(this.students);

  @override
  Future<PagedResult<Student>> fetchStudents({
    required String schoolId,
    required String branchId,
    StudentStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchStatuses.add(status);
    return PagedResult(
      items: students
          .where((s) => status == null || s.status == status)
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<PagedResult<Student>> searchStudentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    nameSearches.add(query);
    return PagedResult(
      items: students
          .where(
            (s) => s.displayName.toLowerCase().startsWith(query.toLowerCase()),
          )
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<PagedResult<Student>> searchStudentsByAdmissionNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    admissionSearches.add(query);
    return PagedResult(
      items: students
          .where(
            (s) =>
                s.admissionNumber.toLowerCase().startsWith(query.toLowerCase()),
          )
          .toList(),
      nextCursor: null,
    );
  }

  /// Every placement query the UI made: (year, class, section).
  final List<({String year, String classId, String? sectionId})>
  placementCalls = [];

  @override
  Future<PagedResult<Student>> fetchStudentsByPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    placementCalls.add((
      year: academicYearId,
      classId: classId,
      sectionId: sectionId,
    ));
    return PagedResult(
      items: students
          .where(
            (s) =>
                s.currentAcademicYearId == academicYearId &&
                s.currentClassId == classId &&
                (sectionId == null || s.currentSectionId == sectionId),
          )
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<int> countStudents({
    required String schoolId,
    required String branchId,
    StudentStatus? status,
  }) async {
    countCalls.add(status);
    return students.where((s) => status == null || s.status == status).length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
