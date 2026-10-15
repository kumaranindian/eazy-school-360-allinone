import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_structure_repository.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/class_subject_link.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/staff/domain/department.dart';
import 'package:eazy_school_360/features/staff/domain/designation.dart';
import 'package:eazy_school_360/features/staff/domain/employment_type.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';
import 'package:eazy_school_360/features/staff/domain/staff_document.dart';
import 'package:eazy_school_360/features/staff/domain/staff_repository.dart';
import 'package:eazy_school_360/features/staff/domain/staff_search_field.dart';
import 'package:eazy_school_360/features/staff/domain/staff_setup_repository.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_repository.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';

Staff fakeStaff(
  String id, {
  String first = 'Priya',
  String last = 'Sharma',
  String code = 'EMP-0001',
  StaffStatus status = StaffStatus.active,
  bool isTeacher = false,
  String? userId,
  String departmentId = 'academic',
  String designationId = 'teacher',
}) {
  return Staff(
    staffId: id,
    schoolId: 'school-1',
    branchId: 'main',
    employeeCode: code,
    firstName: first,
    lastName: last,
    dateOfBirth: DateTime(1990, 5, 1),
    gender: Gender.female,
    phone: '9876543210',
    joiningDate: DateTime(2020, 6, 1),
    employmentType: EmploymentType.fullTime,
    departmentId: departmentId,
    designationId: designationId,
    status: status,
    isTeacher: isTeacher,
    userId: userId,
  );
}

/// A [StaffRepository] fake that serves a canned list and records the
/// arguments of the calls the UI makes. Methods the tests don't exercise
/// throw via [noSuchMethod].
class FakeStaffRepository implements StaffRepository {
  List<Staff> staff;
  Object? error;
  final List<Map<String, Object?>> fetchCalls = [];
  final List<Map<String, Object?>> searchCalls = [];

  FakeStaffRepository({this.staff = const [], this.error});

  @override
  Future<PagedResult<Staff>> fetchStaff({
    required String schoolId,
    required String branchId,
    StaffStatus? status,
    String? departmentId,
    String? designationId,
    EmploymentType? employmentType,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchCalls.add({
      'status': status,
      'departmentId': departmentId,
      'designationId': designationId,
      'employmentType': employmentType,
      'isTeacher': isTeacher,
    });
    if (error != null) throw error!;
    final matching = staff
        .where((s) => status == null || s.status == status)
        .toList();
    return PagedResult(items: matching, nextCursor: null);
  }

  @override
  Future<List<Staff>> getStaffByIds(
    String schoolId,
    String branchId,
    List<String> staffIds,
  ) async => staff.where((s) => staffIds.contains(s.staffId)).toList();

  final List<StaffStatus?> countCalls = [];

  @override
  Future<int> countStaff({
    required String schoolId,
    required String branchId,
    StaffStatus? status,
    bool? isTeacher,
  }) async {
    countCalls.add(status);
    if (error != null) throw error!;
    return staff
        .where((s) => status == null || s.status == status)
        .where((s) => isTeacher == null || s.isTeacher == isTeacher)
        .length;
  }

  @override
  Future<PagedResult<Staff>> searchStaff({
    required String schoolId,
    required String branchId,
    required StaffSearchField field,
    required String query,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  }) async {
    searchCalls.add({'field': field, 'query': query});
    final lower = query.toLowerCase();
    return PagedResult(
      items: staff
          .where((s) => s.displayName.toLowerCase().startsWith(lower))
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<Staff?> findStaffByUserId(
    String schoolId,
    String branchId,
    String userId,
  ) async => staff.where((s) => s.userId == userId).firstOrNull;

  @override
  Stream<Staff?> watchStaff(String schoolId, String branchId, String staffId) =>
      Stream.value(staff.where((s) => s.staffId == staffId).firstOrNull);

  @override
  Stream<List<StaffDocument>> watchDocuments(
    String schoolId,
    String branchId,
    String staffId,
  ) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStaffSetupRepository implements StaffSetupRepository {
  final List<Department> departments;
  final List<Designation> designations;

  FakeStaffSetupRepository({
    List<Department>? departments,
    List<Designation>? designations,
  }) : departments =
           departments ??
           const [
             Department(
               departmentId: 'academic',
               schoolId: 'school-1',
               branchId: 'main',
               name: 'Academic',
               code: 'ACADEMIC',
               status: ActivationStatus.active,
             ),
           ],
       designations =
           designations ??
           const [
             Designation(
               designationId: 'teacher',
               schoolId: 'school-1',
               branchId: 'main',
               name: 'Teacher',
               code: 'TEACHER',
               status: ActivationStatus.active,
             ),
           ];

  @override
  Stream<List<Department>> watchDepartments(String schoolId, String branchId) =>
      Stream.value(departments);

  @override
  Stream<List<Designation>> watchDesignations(
    String schoolId,
    String branchId,
  ) => Stream.value(designations);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAcademicStructureRepository implements AcademicStructureRepository {
  final List<AcademicYear> years;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;

  /// classId -> ids of the subjects linked to that class.
  final Map<String, List<String>> classSubjectIds;

  FakeAcademicStructureRepository({
    this.years = const [],
    this.classes = const [],
    this.sections = const [],
    this.subjects = const [],
    this.classSubjectIds = const {},
  });

  @override
  Stream<List<AcademicYear>> watchAcademicYears(
    String schoolId,
    String branchId,
  ) => Stream.value(years);

  @override
  Future<AcademicYear?> getAcademicYear(
    String schoolId,
    String branchId,
    String academicYearId,
  ) async => years.where((y) => y.academicYearId == academicYearId).firstOrNull;

  @override
  Stream<List<SchoolClass>> watchClasses(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(
    classes.where((c) => c.academicYearId == academicYearId).toList(),
  );

  @override
  Stream<List<Section>> watchSections(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  ) => Stream.value(
    sections
        .where(
          (s) => s.academicYearId == academicYearId && s.classId == classId,
        )
        .toList(),
  );

  @override
  Stream<List<Subject>> watchSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(
    subjects.where((s) => s.academicYearId == academicYearId).toList(),
  );

  @override
  Stream<List<ClassSubjectLink>> watchClassSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  ) {
    final ids = classSubjectIds[classId] ?? const [];
    return Stream.value([
      for (final subject in subjects.where((s) => ids.contains(s.subjectId)))
        ClassSubjectLink(
          subjectId: subject.subjectId,
          schoolId: schoolId,
          branchId: branchId,
          academicYearId: academicYearId,
          classId: classId,
          subjectName: subject.name,
          subjectType: subject.type,
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records `assignTeacher` / `endAssignment` calls and can be told to
/// refuse them with a [ValidationFailure]-style error.
class FakeTeacherAssignmentRepository implements TeacherAssignmentRepository {
  final List<Map<String, Object?>> assigned = [];
  Object? assignError;

  @override
  Future<String> assignTeacher({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String teacherStaffId,
    required String classId,
    required String sectionId,
    String? subjectId,
    required bool isClassTeacher,
    required DateTime startDate,
    required String createdBy,
  }) async {
    if (assignError != null) throw assignError!;
    assigned.add({
      'academicYearId': academicYearId,
      'teacherStaffId': teacherStaffId,
      'classId': classId,
      'sectionId': sectionId,
      'subjectId': subjectId,
      'isClassTeacher': isClassTeacher,
      'createdBy': createdBy,
    });
    return 'new-assignment';
  }

  List<TeacherAssignment> existing = [];

  @override
  Future<PagedResult<TeacherAssignment>> fetchActiveAssignments({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    String? sectionId,
    String? subjectId,
    int pageSize = 25,
    Object? cursor,
  }) async => PagedResult(
    items: [
      for (final a in existing)
        if (a.academicYearId == academicYearId &&
            a.status == TeacherAssignmentStatus.active &&
            (classId == null || a.classId == classId) &&
            (sectionId == null || a.sectionId == sectionId) &&
            (subjectId == null || a.subjectId == subjectId))
          a,
    ],
    nextCursor: null,
  );

  @override
  Future<List<TeacherAssignment>> fetchAssignmentsForTeachers({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required List<String> teacherStaffIds,
  }) async => [
    for (final a in existing)
      if (a.academicYearId == academicYearId &&
          teacherStaffIds.contains(a.teacherStaffId))
        a,
  ];

  @override
  Stream<List<TeacherAssignment>> watchTeacherAssignments(
    String schoolId,
    String branchId,
    String teacherStaffId, {
    int limit = 300,
  }) => Stream.value(
    existing.where((a) => a.teacherStaffId == teacherStaffId).toList(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
