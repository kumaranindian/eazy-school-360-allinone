import 'fee_enums.dart';

/// The period an invoice bills for. [key] is part of the invoice's document
/// id (so "one invoice per student per period" is structural) and of each
/// line's charge key; it uses only letters, digits and `-`.
class BillingPeriod {
  final FeeFrequency kind;
  final String key;
  final String label;

  const BillingPeriod._(this.kind, this.key, this.label);

  static const _months = [
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

  factory BillingPeriod.monthly(int year, int month) {
    assert(month >= 1 && month <= 12);
    return BillingPeriod._(
      FeeFrequency.monthly,
      'M-$year-${month.toString().padLeft(2, '0')}',
      '${_months[month - 1]} $year',
    );
  }

  factory BillingPeriod.quarterly(int year, int quarter) {
    assert(quarter >= 1 && quarter <= 4);
    return BillingPeriod._(
      FeeFrequency.quarterly,
      'Q-$year-$quarter',
      'Quarter $quarter $year',
    );
  }

  factory BillingPeriod.halfYearly(int year, int half) {
    assert(half == 1 || half == 2);
    return BillingPeriod._(
      FeeFrequency.halfYearly,
      'H-$year-$half',
      'Half $half $year',
    );
  }

  factory BillingPeriod.annual(int year) =>
      BillingPeriod._(FeeFrequency.annual, 'A-$year', 'Year $year');

  /// A named, one-off billing run ("Admission 2026"). Each fee marked
  /// one-time is charged only once per student, whichever label it is billed
  /// under (see [chargeKeyFor]).
  factory BillingPeriod.oneTime(String label) =>
      BillingPeriod._(FeeFrequency.oneTime, 'O-${slug(label)}', label.trim());

  /// A custom period ("Term 1", "Annual day"), billed once per label.
  factory BillingPeriod.custom(String label) =>
      BillingPeriod._(FeeFrequency.custom, 'C-${slug(label)}', label.trim());

  /// Letters/digits/`-` only, so it is safe inside a document id.
  static String slug(String label) {
    final s = label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'x' : s;
  }

  /// Why this period cannot be used, or null.
  static String? validateLabel(String label) {
    if (label.trim().length < 3) {
      return 'Enter a name of at least 3 characters.';
    }
    if (label.trim().length > 40) return 'Keep the name under 40 characters.';
    return null;
  }

  /// A recurring fee is charged once per period; a one-time fee only once
  /// ever — so its charge key ignores the period.
  static String chargeKeyFor(FeeFrequency frequency, String periodKey) =>
      frequency == FeeFrequency.oneTime ? 'ONCE' : periodKey;

  /// Document id of an invoice: one per student, academic year and period.
  static String invoiceId(
    String studentId,
    String academicYearId,
    String periodKey,
  ) => '${studentId}__${academicYearId}__$periodKey';
}
