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

  /// How many students have [status] (all of them when null), counted by
  /// the server: one aggregate read, never a download of the documents.
  Future<int> countStudents({
    required String schoolId,
    required String branchId,
    StudentStatus? status,
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

  /// Moves an ACTIVE student to another branch of the same school (school admin
  /// only), as one atomic batch — see `BranchTransferWrites`. History stays in
  /// the old branch; the new branch gets the student already placed, plus the
  /// guardians. Returns the audit entry's id.
  Future<String> transferToBranch({
    required String schoolId,
    required String fromBranchId,
    required String studentId,
    required String toBranchId,
    required String admissionNumber,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    String? reason,
    required DateTime effectiveDate,
    required String updatedBy,
  });

  /// Adds an extra class (e.g. the afternoon day-care class of a child who is
  /// in pre-school in the morning) without touching the main class: one new
  /// ACTIVE `academicRecords` document of kind EXTRA plus the student's cache,
  /// in one transaction. Fails if it duplicates the main class or another
  /// extra, or when the student already has the maximum.
  Future<void> addExtraPlacement({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String label = '',
    String? rollNumber,
    required String updatedBy,
  });

  /// Ends an extra class: its record is closed (kept in the history) and it
  /// leaves the student's cache.
  Future<void> removeExtraPlacement({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String recordId,
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
