import 'payroll.dart';
import '../../expenses/domain/expense.dart' show PaymentMode;
import 'payroll_preview.dart';
import 'payroll_register.dart';
import 'payroll_run.dart';
import 'payslip_document.dart';

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
    bool allowSelfApproval = false,
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

  // ---- runs (phase P3) ----

  Future<PayrollRunList> runs(String schoolId, String branchId);

  Future<PayrollRunDetail> run(String schoolId, String branchId, String period);

  Future<Payslip> payslip(
    String schoolId,
    String branchId,
    String period,
    String staffId,
  );

  Future<List<RunHistoryEntry>> runHistory(
    String schoolId,
    String branchId,
    String period,
  );

  /// Creates the month's run and calculates it. One run per branch and month.
  Future<void> createRun(String schoolId, String branchId, String period);

  Future<void> recalculateRun(
    String schoolId,
    String branchId,
    String period, {
    int? baseVersion,
  });

  Future<void> addAdjustment(
    String schoolId,
    String branchId,
    String period,
    String staffId, {
    required PayKind kind,
    required String label,
    required int amountMinor,
    required String reason,
    int? baseVersion,
  });

  Future<void> removeAdjustment(
    String schoolId,
    String branchId,
    String period,
    String staffId,
    String adjustmentId, {
    int? baseVersion,
  });

  Future<void> approveRun(
    String schoolId,
    String branchId,
    String period, {
    required bool acknowledgeWarnings,
    int? baseVersion,
  });

  Future<void> payRun(
    String schoolId,
    String branchId,
    String period, {
    required PaymentMode mode,
    String? reference,
    String? paidDate,
    int? baseVersion,
  });

  Future<void> cancelRun(
    String schoolId,
    String branchId,
    String period, {
    required String reason,
    int? baseVersion,
  });

  // ---- a staff member's own payslips (phase P4) ----

  /// The months the signed-in staff member has been paid, newest first.
  Future<List<MyPayslipSummary>> myPayslips(String schoolId);

  /// One of their own payslips (the server finds the staff record from the
  /// sign-in; no staff id is sent).
  Future<PayslipDocument> myPayslip(
    String schoolId,
    String branchId,
    String period,
  );

  // ---- the payroll register (phase P5) ----

  /// What was PAID between [fromPeriod] and [toPeriod] (`yyyy-mm`), for the
  /// branch.
  Future<PayrollRegister> register(
    String schoolId,
    String branchId, {
    required String fromPeriod,
    required String toPeriod,
  });

  /// The CSV of one paid run: one row per person, one column per component.
  Future<({String csv, int rows})> exportRegister(
    String schoolId,
    String branchId,
    String period,
  );
}
