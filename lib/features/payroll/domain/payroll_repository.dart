import 'payroll.dart';
import 'payroll_preview.dart';

/// Payroll data. Every call goes through a Cloud Function: clients have no
/// Firestore rules for pay data, so a salary can be neither written nor read
/// around the role and branch checks.
abstract interface class PayrollRepository {
  Future<({List<PayComponent> components, bool canManage})> components(
    String schoolId, {
    bool includeInactive = false,
  });

  /// Adds (no [componentId]) or updates a component; returns its id.
  Future<String> saveComponent(
    String schoolId, {
    String? componentId,
    required String name,
    PayKind? kind,
    PayCalc? calc,
    String? basisComponentId,
    int? percentBp,
    bool? active,
  });

  Future<({List<StaffPaySummary> staff, String currency})> staffPay(
    String schoolId,
    String branchId,
  );

  Future<SalaryStructureView> structure(
    String schoolId,
    String branchId,
    String staffId,
  );

  Future<({PayrollSettings settings, bool canManage})> payrollSettings(
    String schoolId,
  );

  /// Returns the new version.
  Future<int> savePayrollSettings(
    String schoolId,
    UnmarkedDays unmarkedDays, {
    int? baseVersion,
  });

  /// What every current staff member of the branch would be paid for
  /// [period] (`yyyy-mm`). Nothing is saved.
  Future<PayPreviewBranch> previewBranch(
    String schoolId,
    String branchId,
    String period,
  );

  /// The full explanation of one person's month.
  Future<PayPreviewStaff> previewStaff(
    String schoolId,
    String branchId,
    String staffId,
    String period,
  );

  /// Saves a NEW version; returns its number. [reason] is required from the
  /// second version on. [baseSeq] is the version the screen was showing.
  Future<int> saveStructure(
    String schoolId,
    String branchId,
    String staffId, {
    required String effectiveFrom,
    required List<SalaryLineInput> lines,
    String? reason,
    int? baseSeq,
  });
}
