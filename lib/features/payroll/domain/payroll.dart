/// Staff payroll, phase P1 (docs/expense-management/ section 6): pay
/// components and a staff member's salary structure.
///
/// Money is an integer number of minor units of the school's one currency.
/// The arithmetic here ([PayrollPreview]) mirrors `functions/payroll_math.js`
/// so the editor can show the net pay while typing; the server always
/// recomputes and is the only authority.
library;

enum PayKind {
  earning('EARNING', 'Earning'),
  deduction('DEDUCTION', 'Deduction');

  final String wire;
  final String label;
  const PayKind(this.wire, this.label);

  static PayKind fromWire(Object? v) =>
      v == 'DEDUCTION' ? PayKind.deduction : PayKind.earning;
}

enum PayCalc {
  fixed('FIXED', 'Fixed amount'),
  percent('PERCENT', 'Percentage of another earning');

  final String wire;
  final String label;
  const PayCalc(this.wire, this.label);

  static PayCalc fromWire(Object? v) =>
      v == 'PERCENT' ? PayCalc.percent : PayCalc.fixed;
}

/// A school-defined earning or deduction. What it IS (kind, calculation,
/// basis) never changes after creation; only its name, whether it is in use
/// and a percentage's default can.
class PayComponent {
  final String id;
  final String name;
  final PayKind kind;
  final PayCalc calc;
  final String? basisComponentId;

  /// Hundredths of a percent (1250 = 12.50%); null for a fixed component.
  final int? percentBp;
  final bool active;
  final bool system;

  const PayComponent({
    required this.id,
    required this.name,
    required this.kind,
    required this.calc,
    this.basisComponentId,
    this.percentBp,
    this.active = true,
    this.system = false,
  });

  factory PayComponent.fromMap(Map<String, dynamic> m) => PayComponent(
    id: (m['id'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    kind: PayKind.fromWire(m['kind']),
    calc: PayCalc.fromWire(m['calc']),
    basisComponentId: m['basisComponentId'] as String?,
    percentBp: (m['percentBp'] as num?)?.toInt(),
    active: m['active'] != false,
    system: m['system'] == true,
  );

  /// Null when [name] is acceptable (2-60 characters, not already used).
  static String? validateName(
    String name,
    Iterable<PayComponent> existing, {
    String? exceptId,
  }) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.length < 2 || n.length > 60) return 'Use 2 to 60 characters.';
    final taken = existing.any(
      (c) => c.id != exceptId && c.name.toLowerCase() == n.toLowerCase(),
    );
    return taken ? 'A component with that name already exists.' : null;
  }
}

/// One line of a stored structure (a snapshot: the name is as it was when the
/// version was saved).
class SalaryLine {
  final String componentId;
  final String name;
  final PayKind kind;
  final PayCalc calc;
  final int amountMinor;
  final int? percentBp;
  final String? basisId;

  const SalaryLine({
    required this.componentId,
    required this.name,
    required this.kind,
    required this.calc,
    required this.amountMinor,
    this.percentBp,
    this.basisId,
  });

  factory SalaryLine.fromMap(Map<String, dynamic> m) => SalaryLine(
    componentId: (m['componentId'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    kind: PayKind.fromWire(m['kind']),
    calc: PayCalc.fromWire(m['calc']),
    amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
    percentBp: (m['percentBp'] as num?)?.toInt(),
    basisId: m['basisId'] as String?,
  );
}

/// One version of a salary structure.
class SalaryStructure {
  final String id;
  final String staffId;
  final int seq;

  /// `yyyy-mm-01`.
  final String effectiveFrom;
  final String currency;
  final List<SalaryLine> lines;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;
  final bool latest;
  final String? reason;

  const SalaryStructure({
    required this.id,
    required this.staffId,
    required this.seq,
    required this.effectiveFrom,
    required this.currency,
    required this.lines,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    required this.latest,
    this.reason,
  });

  factory SalaryStructure.fromMap(Map<String, dynamic> m) => SalaryStructure(
    id: (m['id'] as String?) ?? '',
    staffId: (m['staffId'] as String?) ?? '',
    seq: (m['seq'] as num?)?.toInt() ?? 0,
    effectiveFrom: (m['effectiveFrom'] as String?) ?? '',
    currency: (m['currency'] as String?) ?? '',
    lines: [
      for (final l in (m['lines'] as List? ?? const []))
        SalaryLine.fromMap(Map<String, dynamic>.from(l as Map)),
    ],
    grossMinor: (m['grossMinor'] as num?)?.toInt() ?? 0,
    deductionsMinor: (m['deductionsMinor'] as num?)?.toInt() ?? 0,
    netMinor: (m['netMinor'] as num?)?.toInt() ?? 0,
    latest: m['latest'] == true,
    reason: m['reason'] as String?,
  );
}

class StaffPay {
  final String id;
  final String name;
  final String employeeCode;
  final String status;

  const StaffPay({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.status,
  });
}

/// A staff member's structure in force today, and every version.
class SalaryStructureView {
  final StaffPay staff;
  final SalaryStructure? current;
  final List<SalaryStructure> history;
  final bool canEdit;

  /// The school's currency (for amounts and the editor).
  final String currency;

  const SalaryStructureView({
    required this.staff,
    required this.current,
    required this.history,
    required this.canEdit,
    required this.currency,
  });
}

/// A row of the branch's pay list: totals only, never the lines.
class StaffPaySummary {
  final StaffPay staff;
  final bool hasStructure;
  final String? effectiveFrom;
  final int? grossMinor;
  final int? deductionsMinor;
  final int? netMinor;

  const StaffPaySummary({
    required this.staff,
    required this.hasStructure,
    this.effectiveFrom,
    this.grossMinor,
    this.deductionsMinor,
    this.netMinor,
  });
}

/// What the editor sends for one component: the server takes everything else
/// (kind, calculation, basis, name) from the school's component.
class SalaryLineInput {
  final String componentId;
  final int? amountMinor;
  final int? percentBp;

  const SalaryLineInput({
    required this.componentId,
    this.amountMinor,
    this.percentBp,
  });

  Map<String, dynamic> toRequest() => {
    'componentId': componentId,
    'amountMinor': ?amountMinor,
    'percentBp': ?percentBp,
  };
}

/// The live total of an editor, with the same rules as the server.
class PayrollPreview {
  final bool valid;
  final String? problem;
  final int grossMinor;
  final int deductionsMinor;
  final int netMinor;

  /// Computed amount per component id.
  final Map<String, int> amounts;

  const PayrollPreview._({
    required this.valid,
    this.problem,
    this.grossMinor = 0,
    this.deductionsMinor = 0,
    this.netMinor = 0,
    this.amounts = const {},
  });

  static const int maxMinor = 1000000000000;

  /// Percentage of [base], rounded half up, exact for any 64-bit or web
  /// number (BigInt).
  static int percentOf(int base, int bp) =>
      ((BigInt.from(base) * BigInt.from(bp) + BigInt.from(5000)) ~/
              BigInt.from(10000))
          .toInt();

  static PayrollPreview compute(
    List<SalaryLineInput> lines,
    Map<String, PayComponent> components,
  ) {
    if (lines.isEmpty) {
      return const PayrollPreview._(
        valid: false,
        problem: 'Add at least one earning.',
      );
    }
    final amounts = <String, int>{};
    for (final l in lines) {
      final c = components[l.componentId];
      if (c == null) {
        return const PayrollPreview._(
          valid: false,
          problem: 'A component is not available.',
        );
      }
      if (c.calc == PayCalc.fixed) {
        final a = l.amountMinor;
        if (a == null || a < 1 || a > maxMinor) {
          return PayrollPreview._(
            valid: false,
            problem: 'Enter an amount for ${c.name}.',
          );
        }
        amounts[c.id] = a;
      }
    }
    for (final l in lines) {
      final c = components[l.componentId]!;
      if (c.calc != PayCalc.percent) continue;
      final bp = l.percentBp ?? c.percentBp;
      final base = c.basisComponentId == null
          ? null
          : amounts[c.basisComponentId];
      if (bp == null || bp < 1 || bp > 10000) {
        return PayrollPreview._(
          valid: false,
          problem: 'Enter a percentage for ${c.name}.',
        );
      }
      if (base == null) {
        return PayrollPreview._(
          valid: false,
          problem: '${c.name} needs its basis in this structure.',
        );
      }
      amounts[c.id] = percentOf(base, bp);
    }
    var gross = 0;
    var ded = 0;
    for (final l in lines) {
      final c = components[l.componentId]!;
      if (c.kind == PayKind.earning) {
        gross += amounts[c.id]!;
      } else {
        ded += amounts[c.id]!;
      }
    }
    if (gross == 0) {
      return const PayrollPreview._(
        valid: false,
        problem: 'Add at least one earning.',
      );
    }
    if (ded > gross) {
      return PayrollPreview._(
        valid: false,
        problem: 'Deductions are more than the earnings.',
        grossMinor: gross,
        deductionsMinor: ded,
        netMinor: gross - ded,
        amounts: amounts,
      );
    }
    return PayrollPreview._(
      valid: true,
      grossMinor: gross,
      deductionsMinor: ded,
      netMinor: gross - ded,
      amounts: amounts,
    );
  }
}

/// The 1st of a month as `yyyy-mm-01`, for the effective-date picker.
String firstOfMonth(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';

/// Basis points as text: 1250 -> "12.5%", 4000 -> "40%".
String percentText(int bp) {
  final whole = bp ~/ 100;
  final frac = bp % 100;
  if (frac == 0) return '$whole%';
  final f = frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
  return '$whole.$f%';
}

/// Parses what a person types ("12.5") into basis points, or null.
int? parsePercentBp(String input) {
  final m = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(input.trim());
  if (m == null) return null;
  final bp =
      int.parse(m.group(1)!) * 100 +
      (m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0')));
  return bp < 1 || bp > 10000 ? null : bp;
}
