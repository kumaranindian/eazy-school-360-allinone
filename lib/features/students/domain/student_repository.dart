import 'academic_record_status.dart';
import 'paged_result.dart';
import 'parent_student_link.dart';
import 'relationship_type.dart';
import 'student.dart';
import 'student_academic_record.dart';
import 'student_status.dart';

/// Students and everything that nests under a student:
/// `academicRecords` (the real academic-history source of truth) and
/// `parentLinks` (the student side of the parent-student relationship —
/// see `ParentRepository` for the parent side and the cross-student
/// lookup). See `docs/milestone-3-student-parent-management.md`.
abstract class StudentRepository {
  /// Default roster view: one Firestore equality filter (status, or no
  /// filter) plus `orderBy displayNameLower`, cursor-paginated — never an
  /// unbounded fetch. Combining a class/section filter at the same time is
  /// intentionally not supported here (see docs — avoids a combinatorial
  /// set of composite indexes); use [fetchStudentsByPlacement] for that.
  Future<PagedResult<Student>> fetchStudents({
    required String schoolId,
    required String branchId,
    StudentStatus? status,
    int pageSize = 25,
    Object? cursor,
  });

  /// Students currently placed in a specific class (and, optionally,
  /// section) — reads the current-placement cache on [Student], not the
  /// academic-history subcollection, so this stays cheap.
  Future<PagedResult<Student>> fetchStudentsByPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    int pageSize = 25,
    Object? cursor,
  });

  /// Prefix search on name — see docs for why this (not class/section
  /// filters) is the one dimension combined with free text.
  Future<PagedResult<Student>> searchStudentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  });

  Future<PagedResult<Student>> searchStudentsByAdmissionNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  });

  Future<Student?> getStudent(
    String schoolId,
    String branchId,
    String studentId,
  );

  Stream<Student?> watchStudent(
    String schoolId,
    String branchId,
    String studentId,
  );

  Future<bool> isAdmissionNumberAvailable(
    String schoolId,
    String branchId,
    String admissionNumber, {
    String? excludingStudentId,
  });

  /// Admission (brief §13): creates the student profile AND its first
  /// academic-enrollment record in one atomic batch — a student is never
  /// left in a state where one exists without the other.
  Future<String> admitStudent({
    required Student student,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String createdBy,
  });

  Future<void> updateStudentProfile(
    Student student, {
    required String updatedBy,
  });

  Future<String> uploadStudentPhoto({
    required String schoolId,
    required String branchId,
    required String studentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  });

  Future<void> changeStudentStatus({
    required String schoolId,
    required String branchId,
    required String studentId,
    required StudentStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  });

  /// A placement change (brief §19): closes the current active academic
  /// record as [closeOldRecordAs], creates a new active one for the new
  /// placement, and updates the student's current-placement cache — one
  /// atomic batch, the old record is never overwritten.
  Future<void> transferStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String newAcademicYearId,
    required String newClassId,
    required String newSectionId,
    String? newRollNumber,
    required AcademicRecordStatus closeOldRecordAs,
    required String updatedBy,
  });

  /// Chronological, oldest first — see
  /// `docs/milestone-3-student-parent-management.md` → "Academic History
  /// UI".
  Stream<List<StudentAcademicRecord>> watchAcademicHistory(
    String schoolId,
    String branchId,
    String studentId,
  );

  Stream<List<ParentStudentLink>> watchParentLinks(
    String schoolId,
    String branchId,
    String studentId,
  );

  Future<void> linkParentToStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String parentId,
    required RelationshipType relationshipType,
    bool isPrimary = false,
    bool isEmergencyContact = false,
    bool canAccessPortal = false,
    required String createdBy,
  });

  Future<void> updateParentLink(
    ParentStudentLink link, {
    required String updatedBy,
  });
}
