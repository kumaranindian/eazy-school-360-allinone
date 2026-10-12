import '../../students/domain/paged_result.dart';
import 'teacher_assignment.dart';

/// Academic-year-aware teaching assignments (subject teaching and class
/// teacher). Throws an `AppFailure` (via error_mapper) on failure.
abstract class TeacherAssignmentRepository {
  /// Every assignment this teacher has ever had, active and ended, newest
  /// first — the "assignment history". Bounded by [limit].
  Stream<List<TeacherAssignment>> watchTeacherAssignments(
    String schoolId,
    String branchId,
    String teacherStaffId, {
    int limit = 300,
  });

  /// ACTIVE assignments in one academic year, narrowed by whichever of
  /// class / section / subject are given; cursor-paginated. Used by the
  /// teacher list's class/section/subject filters.
  Future<PagedResult<TeacherAssignment>> fetchActiveAssignments({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    String? sectionId,
    String? subjectId,
    int pageSize = 25,
    Object? cursor,
  });

  /// Assignments of the given teachers in one academic year (any status),
  /// so a page of teachers can show their classes/subjects with one
  /// query per 30 teachers instead of one per teacher.
  Future<List<TeacherAssignment>> fetchAssignmentsForTeachers({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required List<String> teacherStaffIds,
  });

  /// Active assignments for one section (its subject teachers and class
  /// teacher).
  Stream<List<TeacherAssignment>> watchSectionAssignments(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String sectionId,
  );

  /// Creates an assignment and its uniqueness slot in one batch, after
  /// validating every reference (see the implementation, and the matching
  /// `firestore.rules`, which re-check them server-side). Pass a null
  /// [subjectId] with [isClassTeacher] true for a class-teacher
  /// assignment. Throws [ValidationFailure] with a user-readable reason.
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
  });

  /// Ends an active assignment (status ENDED + end date) and releases its
  /// slot, atomically. The row is kept as history.
  Future<void> endAssignment({
    required TeacherAssignment assignment,
    required DateTime endDate,
    required String updatedBy,
  });
}
