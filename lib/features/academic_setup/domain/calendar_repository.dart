import 'holiday.dart';
import 'working_days.dart';

/// Boundary for the working-days pattern and the holiday calendar.
/// Throws an `AppFailure` (via error_mapper) on failure.
abstract class CalendarRepository {
  Future<WorkingDays> getWorkingDays(String schoolId, String branchId);

  Future<void> setWorkingDays(
    WorkingDays workingDays, {
    required String updatedBy,
  });

  /// Whether a branch has actually saved a working-days pattern, as
  /// distinct from [getWorkingDays] silently returning Mon-Fri defaults
  /// for a branch that's never touched this setting. Used by
  /// `setup_status_provider.dart` — a real checklist item needs to know
  /// "configured" from "defaulted," not just always read `true`.
  Future<bool> hasWorkingDaysConfigured(String schoolId, String branchId);

  Stream<List<Holiday>> watchHolidays(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  /// Throws a [ValidationFailure] if a holiday already exists on the same
  /// calendar day for this branch + academic year.
  Future<String> createHoliday(Holiday holiday, {required String createdBy});

  Future<void> updateHoliday(Holiday holiday, {required String updatedBy});
}
