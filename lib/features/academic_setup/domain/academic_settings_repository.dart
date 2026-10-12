import 'academic_settings.dart';

/// Boundary for the small branch-wide settings document. Throws an
/// `AppFailure` (via error_mapper) on failure.
abstract class AcademicSettingsRepository {
  Future<AcademicSettings> getSettings(String schoolId, String branchId);

  Future<void> updateSettings(
    AcademicSettings settings, {
    required String updatedBy,
  });
}
