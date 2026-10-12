import 'department.dart';
import 'designation.dart';

/// Department and designation configuration for a branch. Throws a
/// [ValidationFailure] on a duplicate code, an `AppFailure` otherwise.
abstract class StaffSetupRepository {
  Stream<List<Department>> watchDepartments(String schoolId, String branchId);

  Future<String> createDepartment(
    Department department, {
    required String createdBy,
  });

  /// Name, description and status only — the code is the document id.
  Future<void> updateDepartment(
    Department department, {
    required String updatedBy,
  });

  Stream<List<Designation>> watchDesignations(String schoolId, String branchId);

  Future<String> createDesignation(
    Designation designation, {
    required String createdBy,
  });

  Future<void> updateDesignation(
    Designation designation, {
    required String updatedBy,
  });
}
