/// The payroll register (phase P5): what was actually PAID, month by month.
library;

class RegisterRow {
  final String branchId;
  final String branchName;
  final String period;
  final int payslipCount;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final int unrecoveredDeductionMinor;
  final String? paidDate;
  final String? paymentMode;
  final String? expenseNumber;

  const RegisterRow({
    required this.branchId,
    required this.branchName,
    required this.period,
    required this.payslipCount,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    this.unrecoveredDeductionMinor = 0,
    this.paidDate,
    this.paymentMode,
    this.expenseNumber,
  });

  factory RegisterRow.fromMap(Map<String, dynamic> m) => RegisterRow(
    branchId: (m['branchId'] as String?) ?? '',
    branchName: (m['branchName'] as String?) ?? '',
    period: (m['period'] as String?) ?? '',
    payslipCount: (m['payslipCount'] as num?)?.toInt() ?? 0,
    grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
    deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    unrecoveredDeductionMinor:
        (m['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
    paidDate: m['paidDate'] as String?,
    paymentMode: m['paymentMode'] as String?,
    expenseNumber: m['expenseNumber'] as String?,
  );
}

class PayrollRegister {
  final String currency;
  final String fromPeriod;
  final String toPeriod;
  final List<RegisterRow> rows;
  final int runs;
  final int payslipCount;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;

  const PayrollRegister({
    required this.currency,
    required this.fromPeriod,
    required this.toPeriod,
    required this.rows,
    required this.runs,
    required this.payslipCount,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
  });

  factory PayrollRegister.fromMap(Map<String, dynamic> m) {
    final t = Map<String, dynamic>.from((m['totals'] as Map?) ?? const {});
    return PayrollRegister(
      currency: (m['currency'] as String?) ?? '',
      fromPeriod: (m['fromPeriod'] as String?) ?? '',
      toPeriod: (m['toPeriod'] as String?) ?? '',
      rows: [
        for (final r in (m['rows'] as List? ?? const []))
          RegisterRow.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
      runs: (t['runs'] as num?)?.toInt() ?? 0,
      payslipCount: (t['payslipCount'] as num?)?.toInt() ?? 0,
      grossMinor: (t['grossMinor'] as num?)?.toInt() ?? 0,
      deductionsMinor: (t['deductionsMinor'] as num?)?.toInt() ?? 0,
      netMinor: (t['netMinor'] as num?)?.toInt() ?? 0,
    );
  }
}
