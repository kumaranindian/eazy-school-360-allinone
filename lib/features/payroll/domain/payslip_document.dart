/// A payslip as printed and as a staff member reads it, phase P4. Built from
/// the server's answer; nothing is recomputed here.
library;

import '../../expenses/domain/expense.dart' show PaymentMode;
import 'payroll.dart';
import 'payroll_run.dart';

class PayslipDocLine {
  final String name;
  final PayKind kind;
  final int amountMinor;

  /// What the structure said before attendance reduced it (equal to
  /// [amountMinor] when nothing was cut, and for one-off items).
  final int plannedMinor;
  final bool oneOff;

  const PayslipDocLine({
    required this.name,
    required this.kind,
    required this.amountMinor,
    required this.plannedMinor,
    this.oneOff = false,
  });

  bool get reduced => !oneOff && plannedMinor != amountMinor;
}

class PayslipDocument {
  final String schoolName;
  final String branchName;
  final String staffName;
  final String employeeCode;

  /// `yyyy-mm`.
  final String period;
  final String currency;
  final String? paidDate;
  final String? paymentMode;
  final int workingDays;
  final double paidDays;
  final double unpaidDays;
  final List<PayslipDocLine> lines;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final int unrecoveredDeductionMinor;

  const PayslipDocument({
    required this.schoolName,
    required this.branchName,
    required this.staffName,
    required this.employeeCode,
    required this.period,
    required this.currency,
    required this.paidDate,
    required this.paymentMode,
    required this.workingDays,
    required this.paidDays,
    required this.unpaidDays,
    required this.lines,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    this.unrecoveredDeductionMinor = 0,
  });

  Iterable<PayslipDocLine> get earnings =>
      lines.where((l) => l.kind == PayKind.earning);
  Iterable<PayslipDocLine> get deductions =>
      lines.where((l) => l.kind == PayKind.deduction);

  String? get paymentModeLabel =>
      paymentMode == null ? null : PaymentMode.fromWire(paymentMode)?.label;

  /// A file name that is safe on every platform: `Payslip-2026-11-E1.pdf`.
  String get fileName {
    final code = employeeCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'Payslip-$period${code.isEmpty ? '' : '-$code'}.pdf';
  }

  factory PayslipDocument.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>> list(Object? v) => [
      for (final x in (v as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    return PayslipDocument(
      schoolName: (m['schoolName'] as String?) ?? '',
      branchName: (m['branchName'] as String?) ?? '',
      staffName: (m['staffName'] as String?) ?? '',
      employeeCode: (m['employeeCode'] as String?) ?? '',
      period: (m['period'] as String?) ?? '',
      currency: (m['currency'] as String?) ?? '',
      paidDate: m['paidDate'] as String?,
      paymentMode: m['paymentMode'] as String?,
      workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
      paidDays: (m['paidDays'] as num?)?.toDouble() ?? 0,
      unpaidDays: (m['unpaidDays'] as num?)?.toDouble() ?? 0,
      lines: [
        for (final l in list(m['lines']))
          PayslipDocLine(
            name: (l['name'] as String?) ?? '',
            kind: PayKind.fromWire(l['kind']),
            amountMinor: (l['amountMinor'] as num?)?.toInt() ?? 0,
            plannedMinor: (l['plannedMinor'] as num?)?.toInt() ?? 0,
          ),
        for (final a in list(m['adjustments']))
          PayslipDocLine(
            name: (a['label'] as String?) ?? '',
            kind: PayKind.fromWire(a['kind']),
            amountMinor: (a['amountMinor'] as num?)?.toInt() ?? 0,
            plannedMinor: (a['amountMinor'] as num?)?.toInt() ?? 0,
            oneOff: true,
          ),
      ],
      grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
      deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
      netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
      unrecoveredDeductionMinor:
          (m['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
    );
  }

  /// An administrator's payslip of a PAID run, for printing a copy.
  factory PayslipDocument.fromAdmin(
    Payslip p,
    PayrollRun run, {
    required String schoolName,
    required String branchName,
  }) => PayslipDocument(
    schoolName: schoolName,
    branchName: branchName,
    staffName: p.row.name,
    employeeCode: p.row.employeeCode,
    period: run.period,
    currency: p.currency,
    paidDate: run.paidDate,
    paymentMode: run.paymentMode,
    workingDays: p.row.workingDays,
    paidDays: p.row.paidDays,
    unpaidDays: p.row.unpaidDays,
    lines: [
      for (final l in p.lines)
        PayslipDocLine(
          name: l.name,
          kind: l.kind,
          amountMinor: l.amountMinor,
          plannedMinor: l.plannedMinor,
        ),
      for (final a in p.adjustments)
        PayslipDocLine(
          name: a.label,
          kind: a.kind,
          amountMinor: a.amountMinor,
          plannedMinor: a.amountMinor,
          oneOff: true,
        ),
    ],
    grossMinor: p.row.grossMinor,
    deductionsMinor: p.row.deductionsMinor,
    netMinor: p.row.netMinor,
    unrecoveredDeductionMinor: p.unrecoveredDeductionMinor,
  );
}

/// One month in a staff member's list of payslips.
class MyPayslipSummary {
  final String branchId;
  final String period;
  final String? paidDate;
  final int netMinor;
  final String currency;

  const MyPayslipSummary({
    required this.branchId,
    required this.period,
    required this.paidDate,
    required this.netMinor,
    required this.currency,
  });

  factory MyPayslipSummary.fromMap(Map<String, dynamic> m) => MyPayslipSummary(
    branchId: (m['branchId'] as String?) ?? '',
    period: (m['period'] as String?) ?? '',
    paidDate: m['paidDate'] as String?,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    currency: (m['currency'] as String?) ?? '',
  );
}
