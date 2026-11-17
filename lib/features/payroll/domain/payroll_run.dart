/// Payroll runs, phase P3: one run per branch and month.
///
/// DRAFT -> CALCULATED -> APPROVED -> PAID (CANCELLED from any of the first
/// three). The server decides every change; [RunActions] only mirrors its rules
/// to choose which buttons to show.
library;

import 'payroll.dart';

enum RunStatus {
  draft('DRAFT', 'Draft'),
  calculated('CALCULATED', 'Calculated'),
  approved('APPROVED', 'Approved'),
  paid('PAID', 'Paid'),
  cancelled('CANCELLED', 'Cancelled');

  final String wire;
  final String label;
  const RunStatus(this.wire, this.label);

  static RunStatus fromWire(Object? v) => RunStatus.values.firstWhere(
    (s) => s.wire == v,
    orElse: () => RunStatus.draft,
  );
}

class PayrollRun {
  final String period;
  final RunStatus status;
  final int version;
  final String currency;
  final int payslipCount;
  final int skippedCount;
  final int warningCount;
  final int adjustmentCount;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final int unrecoveredDeductionMinor;
  final int workingDays;
  final String? approvedByName;
  final String? paidDate;
  final String? paymentMode;
  final String? paymentReference;
  final String? cancelReason;

  /// The Salaries expense a paid run posted (number and id), once paid.
  final String? expenseId;
  final String? expenseNumber;

  const PayrollRun({
    required this.period,
    required this.status,
    required this.version,
    required this.currency,
    this.payslipCount = 0,
    this.skippedCount = 0,
    this.warningCount = 0,
    this.adjustmentCount = 0,
    this.grossMinor = 0,
    this.deductionsMinor = 0,
    this.netMinor = 0,
    this.unrecoveredDeductionMinor = 0,
    this.workingDays = 0,
    this.approvedByName,
    this.paidDate,
    this.paymentMode,
    this.paymentReference,
    this.cancelReason,
    this.expenseId,
    this.expenseNumber,
  });

  factory PayrollRun.fromMap(Map<String, dynamic> m) => PayrollRun(
    period: (m['period'] as String?) ?? (m['id'] as String?) ?? '',
    status: RunStatus.fromWire(m['status']),
    version: (m['version'] as num?)?.toInt() ?? 1,
    currency: (m['currency'] as String?) ?? '',
    payslipCount: (m['payslipCount'] as num?)?.toInt() ?? 0,
    skippedCount: (m['skippedCount'] as num?)?.toInt() ?? 0,
    warningCount: (m['warningCount'] as num?)?.toInt() ?? 0,
    adjustmentCount: (m['adjustmentCount'] as num?)?.toInt() ?? 0,
    grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
    deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    unrecoveredDeductionMinor:
        (m['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
    workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
    approvedByName: m['approvedByName'] as String?,
    paidDate: m['paidDate'] as String?,
    paymentMode: m['paymentMode'] as String?,
    paymentReference: m['paymentReference'] as String?,
    cancelReason: m['cancelReason'] as String?,
    expenseId: m['expenseId'] as String?,
    expenseNumber: m['expenseNumber'] as String?,
  );

  /// Something the person approving should look at first.
  bool get needsReview => warningCount > 0 || skippedCount > 0;
}

class PayrollRunList {
  final List<PayrollRun> runs;
  final bool canPrepare;
  final bool canApprove;
  final bool canPay;

  const PayrollRunList({
    required this.runs,
    required this.canPrepare,
    required this.canApprove,
    required this.canPay,
  });
}

/// One row of a run's table: totals, never the lines.
class PayslipRow {
  final String staffId;
  final String name;
  final String employeeCode;
  final double paidDays;
  final double unpaidDays;
  final int workingDays;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final int warningCount;
  final int adjustmentCount;

  const PayslipRow({
    required this.staffId,
    required this.name,
    required this.employeeCode,
    required this.paidDays,
    required this.unpaidDays,
    required this.workingDays,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    required this.warningCount,
    required this.adjustmentCount,
  });

  factory PayslipRow.fromMap(Map<String, dynamic> m) => PayslipRow(
    staffId: (m['staffId'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    employeeCode: (m['employeeCode'] as String?) ?? '',
    paidDays: (m['paidDays'] as num?)?.toDouble() ?? 0,
    unpaidDays: (m['unpaidDays'] as num?)?.toDouble() ?? 0,
    workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
    grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
    deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    warningCount: (m['warningCount'] as num?)?.toInt() ?? 0,
    adjustmentCount: (m['adjustmentCount'] as num?)?.toInt() ?? 0,
  );
}

class PayrollRunDetail {
  final PayrollRun run;
  final List<PayslipRow> payslips;
  final int skipped;
  final bool canPrepare;
  final bool canApprove;
  final bool canPay;
  final bool allowSelfApproval;

  const PayrollRunDetail({
    required this.run,
    required this.payslips,
    required this.skipped,
    required this.canPrepare,
    required this.canApprove,
    required this.canPay,
    required this.allowSelfApproval,
  });
}

/// A one-off item added to one payslip (a bonus, a recovery).
class PayAdjustment {
  final String id;
  final PayKind kind;
  final String label;
  final int amountMinor;
  final String reason;

  const PayAdjustment({
    required this.id,
    required this.kind,
    required this.label,
    required this.amountMinor,
    required this.reason,
  });

  factory PayAdjustment.fromMap(Map<String, dynamic> m) => PayAdjustment(
    id: (m['id'] as String?) ?? '',
    kind: PayKind.fromWire(m['kind']),
    label: (m['label'] as String?) ?? '',
    amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
    reason: (m['reason'] as String?) ?? '',
  );
}

/// The whole payslip of one person for a run.
class Payslip {
  final PayslipRow row;
  final String currency;
  final List<PayLineSnapshot> lines;
  final List<PayAdjustment> adjustments;
  final List<String> warnings;
  final int baseGrossMinor;
  final int unrecoveredDeductionMinor;

  const Payslip({
    required this.row,
    required this.currency,
    required this.lines,
    required this.adjustments,
    required this.warnings,
    required this.baseGrossMinor,
    required this.unrecoveredDeductionMinor,
  });
}

class PayLineSnapshot {
  final String name;
  final PayKind kind;
  final int plannedMinor;
  final int amountMinor;

  const PayLineSnapshot({
    required this.name,
    required this.kind,
    required this.plannedMinor,
    required this.amountMinor,
  });

  bool get reduced => plannedMinor != amountMinor;
}

class RunHistoryEntry {
  final int seq;
  final String action;
  final String? from;
  final String? to;
  final String? reason;
  final String? actorName;
  final String? actorRole;
  final int? atMs;

  const RunHistoryEntry({
    required this.seq,
    required this.action,
    this.from,
    this.to,
    this.reason,
    this.actorName,
    this.actorRole,
    this.atMs,
  });

  /// "Calculated", "Approved", ... for the timeline.
  String get label => switch (action) {
    'create' => to == 'CALCULATED' ? 'Created and calculated' : 'Created',
    'calculate' => 'Recalculated',
    'adjust' => 'Adjustment added',
    'adjustRemove' => 'Adjustment removed',
    'approve' => 'Approved',
    'pay' => 'Paid',
    'cancel' => 'Cancelled',
    _ => action,
  };
}

/// Which buttons a run offers. Mirrors the server (`functions/payroll_runs.js`
/// `CAP`, `TRANSITIONS`); the server decides.
abstract final class RunActions {
  static bool canRecalculate(PayrollRunDetail d) =>
      d.canPrepare &&
      (d.run.status == RunStatus.calculated || d.run.status == RunStatus.draft);

  static bool canAdjust(PayrollRunDetail d) =>
      d.canPrepare && d.run.status == RunStatus.calculated;

  static bool canApprove(PayrollRunDetail d) =>
      d.canApprove &&
      d.run.status == RunStatus.calculated &&
      d.run.payslipCount > 0;

  static bool canPay(PayrollRunDetail d) =>
      d.canPay && d.run.status == RunStatus.approved;

  /// A school admin may cancel at any open stage, finance only before approval.
  static bool canCancel(PayrollRunDetail d) {
    final s = d.run.status;
    if (s == RunStatus.calculated || s == RunStatus.draft) return d.canPrepare;
    if (s == RunStatus.approved) return d.canApprove;
    return false;
  }
}
