/// Payroll phase P2: what a month's pay would be, from the salary structure,
/// the branch calendar, staff attendance and approved leave. Nothing is saved
/// (runs and payslips come later). The server does all the arithmetic
/// (`functions/payroll_calculator.js`); the app only shows the result and its
/// explanation.
library;

import 'payroll.dart';

/// What the school does with a school day nobody marked attendance for.
enum UnmarkedDays {
  paid('PAID', 'Pay it (assume present)'),
  unpaid('UNPAID', 'Do not pay it');

  final String wire;
  final String label;
  const UnmarkedDays(this.wire, this.label);

  static UnmarkedDays fromWire(Object? v) =>
      v == 'UNPAID' ? UnmarkedDays.unpaid : UnmarkedDays.paid;
}

class PayrollSettings {
  final UnmarkedDays unmarkedDays;
  final int version;

  const PayrollSettings({
    this.unmarkedDays = UnmarkedDays.paid,
    this.version = 0,
  });

  factory PayrollSettings.fromMap(Map<String, dynamic> m) => PayrollSettings(
    unmarkedDays: UnmarkedDays.fromWire(m['unmarkedDays']),
    version: (m['version'] as num?)?.toInt() ?? 0,
  );
}

/// A thing the school should look at before paying.
class PayWarning {
  final String code;
  final String? date;

  const PayWarning(this.code, this.date);

  factory PayWarning.fromMap(Map<String, dynamic> m) =>
      PayWarning((m['code'] as String?) ?? '', m['date'] as String?);

  /// A sentence for the screen.
  String get text {
    final on = date == null ? '' : ' on $date';
    return switch (code) {
      'NOT_MARKED' => 'Attendance was not marked$on.',
      'LEAVE_AND_PRESENT' => 'Marked present on a day of unpaid leave$on.',
      'LEAVE_OVERLAP' => 'Two approved leaves cover the same day$on.',
      'LEAVE_PAY_TYPE_UNKNOWN' => 'A leave$on has no pay type; it was paid.',
      'NO_WORKING_DAYS' => 'This month has no school days; paid in full.',
      _ => 'Check the record$on.',
    };
  }
}

class PayLineResult {
  final String name;
  final PayKind kind;
  final int plannedMinor;
  final int amountMinor;

  const PayLineResult({
    required this.name,
    required this.kind,
    required this.plannedMinor,
    required this.amountMinor,
  });

  factory PayLineResult.fromMap(Map<String, dynamic> m) => PayLineResult(
    name: (m['name'] as String?) ?? '',
    kind: PayKind.fromWire(m['kind']),
    plannedMinor: (m['plannedMinor'] as num?)?.toInt() ?? 0,
    amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
  );

  bool get reduced => amountMinor != plannedMinor;
}

/// The full explanation of one person's month.
class PayCalculation {
  final int workingDays;
  final double paidDays;
  final double unpaidDays;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final int unrecoveredDeductionMinor;
  final List<PayWarning> warnings;
  final List<PayLineResult> lines;

  /// present, late, halfDay, absent, unmarked, paidLeave, unpaidLeave,
  /// notEmployed.
  final Map<String, num> days;

  const PayCalculation({
    required this.workingDays,
    required this.paidDays,
    required this.unpaidDays,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    required this.unrecoveredDeductionMinor,
    required this.warnings,
    required this.lines,
    required this.days,
  });

  factory PayCalculation.fromMap(Map<String, dynamic> m) => PayCalculation(
    workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
    paidDays: (m['paidDays'] as num?)?.toDouble() ?? 0,
    unpaidDays: (m['unpaidDays'] as num?)?.toDouble() ?? 0,
    grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
    deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    unrecoveredDeductionMinor:
        (m['unrecoveredDeductionMinor'] as num?)?.toInt() ?? 0,
    warnings: [
      for (final w in (m['warnings'] as List? ?? const []))
        PayWarning.fromMap(Map<String, dynamic>.from(w as Map)),
    ],
    lines: [
      for (final l in (m['lines'] as List? ?? const []))
        PayLineResult.fromMap(Map<String, dynamic>.from(l as Map)),
    ],
    days: {
      for (final e in ((m['days'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num?) ?? 0,
    },
  );
}

/// One row of the branch's month: totals only.
class PayPreviewRow {
  final StaffPay staff;
  final bool hasStructure;
  final int workingDays;
  final double paidDays;
  final double unpaidDays;
  final int netMinor;
  final int unrecoveredDeductionMinor;
  final int warningCount;

  const PayPreviewRow({
    required this.staff,
    required this.hasStructure,
    this.workingDays = 0,
    this.paidDays = 0,
    this.unpaidDays = 0,
    this.netMinor = 0,
    this.unrecoveredDeductionMinor = 0,
    this.warningCount = 0,
  });
}

class PayPreviewBranch {
  final String period;
  final String currency;
  final int workingDays;
  final UnmarkedDays unmarkedDays;
  final List<PayPreviewRow> rows;

  const PayPreviewBranch({
    required this.period,
    required this.currency,
    required this.workingDays,
    required this.unmarkedDays,
    required this.rows,
  });
}

class PayPreviewStaff {
  final String period;
  final String currency;
  final StaffPay staff;
  final SalaryStructure? structure;
  final PayCalculation? calculation;

  const PayPreviewStaff({
    required this.period,
    required this.currency,
    required this.staff,
    required this.structure,
    required this.calculation,
  });
}

/// `2026-11` -> "November 2026".
String periodLabel(String period) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final y = period.length >= 4 ? period.substring(0, 4) : period;
  final m = period.length >= 7 ? int.tryParse(period.substring(5, 7)) : null;
  return m == null || m < 1 || m > 12 ? period : '${names[m - 1]} $y';
}

/// The last [count] months ending at ([year], [month]), newest first, as
/// `yyyy-mm`.
List<String> recentPeriods(int year, int month, {int count = 12}) {
  final out = <String>[];
  var y = year;
  var m = month;
  for (var i = 0; i < count; i++) {
    out.add('${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}');
    m--;
    if (m == 0) {
      m = 12;
      y--;
    }
  }
  return out;
}

/// A number of days as text: 21 -> "21", 20.5 -> "20.5".
String daysText(num d) =>
    d == d.roundToDouble() ? d.toInt().toString() : d.toString();
