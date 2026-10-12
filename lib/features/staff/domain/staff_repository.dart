import '../../students/domain/paged_result.dart';
import 'employment_type.dart';
import 'staff.dart';
import 'staff_document.dart';
import 'staff_search_field.dart';
import 'staff_status.dart';

/// Staff master records, their photo, and their documents. Teaching
/// assignments live in `TeacherAssignmentRepository`; departments and
/// designations in `StaffSetupRepository`. Throws an `AppFailure` (via
/// error_mapper) on failure.
abstract class StaffRepository {
  /// Browse view: equality filters on [status] / [departmentId] /
  /// [designationId] / [employmentType] / [isTeacher] (any combination —
  /// Firestore merges the single-filter composite indexes in
  /// `firestore.indexes.json`) ordered by name, cursor-paginated.
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
  });

  /// Prefix search on one [field]. Deliberately not combined with the
  /// browse filters — see `docs/milestone-4-staff-teacher-management.md`
  /// → "Queries and indexes". The one exception is [isTeacher] with
  /// [StaffSearchField.name], which the (isTeacher, displayNameLower)
  /// index serves; other field + isTeacher combinations have no index.
  Future<PagedResult<Staff>> searchStaff({
    required String schoolId,
    required String branchId,
    required StaffSearchField field,
    required String query,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  });

  Future<Staff?> getStaff(String schoolId, String branchId, String staffId);

  /// Several staff by id (used to resolve the teachers behind a set of
  /// assignments). Missing ids are skipped; order follows [staffIds].
  Future<List<Staff>> getStaffByIds(
    String schoolId,
    String branchId,
    List<String> staffIds,
  );

  Stream<Staff?> watchStaff(String schoolId, String branchId, String staffId);

  /// The staff record linked to an application account, or null — how a
  /// signed-in teacher finds their own profile.
  Future<Staff?> findStaffByUserId(
    String schoolId,
    String branchId,
    String userId,
  );

  Future<bool> isEmployeeCodeAvailable(
    String schoolId,
    String branchId,
    String employeeCode, {
    String? excludingStaffId,
  });

  /// Creates the staff record and reserves its employee code in one
  /// atomic batch. Throws [ValidationFailure] if the code is taken or the
  /// department/designation is missing or inactive.
  Future<String> createStaff({required Staff staff, required String createdBy});

  /// Edits the profile. A changed employee code is moved atomically
  /// (new reservation + release of the old). Turning [Staff.isTeacher] off
  /// is refused while the member has active teaching assignments.
  Future<void> updateStaff({required Staff staff, required String updatedBy});

  /// Validates the lifecycle move against [StaffStatus.allowedTransitions].
  /// Moving to a status where [StaffStatus.endsActiveAssignments] also ends
  /// the member's active teaching assignments (history kept) in the same
  /// batch. Never deletes anything.
  Future<void> changeStaffStatus({
    required String schoolId,
    required String branchId,
    required String staffId,
    required StaffStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  });

  /// Links (or, with a null [userId], unlinks) an application account.
  /// Throws [ValidationFailure] if the account doesn't exist, belongs to
  /// another school, or is already linked to a different staff member.
  Future<void> linkUserAccount({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String? userId,
    required String updatedBy,
  });

  Future<String> uploadStaffPhoto({
    required String schoolId,
    required String branchId,
    required String staffId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  });

  Future<void> removeStaffPhoto({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String updatedBy,
  });

  /// Documents that haven't been removed, newest first.
  Stream<List<StaffDocument>> watchDocuments(
    String schoolId,
    String branchId,
    String staffId,
  );

  Future<void> uploadDocument({
    required String schoolId,
    required String branchId,
    required String staffId,
    required StaffDocumentType type,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String createdBy,
  });

  /// Soft removal — the metadata is marked REMOVED and hidden; the file
  /// stays in Storage (Storage rules forbid deletes).
  Future<void> removeDocument({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String documentId,
    required String updatedBy,
  });

  Future<String> getDocumentDownloadUrl(String storagePath);
}
