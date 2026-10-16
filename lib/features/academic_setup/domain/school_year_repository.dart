import 'school_academic_year.dart';

/// School-wide academic years and opening them in branches. Throws an
/// `AppFailure` (via error_mapper) on failure.
abstract class SchoolYearRepository {
  Stream<List<SchoolAcademicYear>> watchSchoolYears(String schoolId);

  /// School admin only. Returns the new year's id.
  Future<String> createSchoolYear(
    SchoolAcademicYear year, {
    required String createdBy,
  });

  /// Archived years can no longer be opened; branches that already opened one
  /// keep it.
  Future<void> setArchived(
    String schoolId,
    String schoolYearId, {
    required bool archived,
    required String updatedBy,
  });

  /// Creates the branch copy (DRAFT) in each branch that does not have it.
  /// One result per branch; a branch that refuses does not stop the others.
  Future<List<OpenYearResult>> openInBranches(
    SchoolAcademicYear year,
    List<String> branchIds, {
    required String createdBy,
  });

  /// Which of [branchIds] already have this year.
  Future<Set<String>> openedIn(
    String schoolId,
    String schoolYearId,
    List<String> branchIds,
  );
}
