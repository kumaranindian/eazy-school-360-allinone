/// The expense report as the server computes it (`getExpenseReport`). Spend
/// means approved plus paid; drafts, submitted, rejected and cancelled
/// expenses are shown apart and never counted as spend. Money is integer
/// minor units of the school's one currency.
library;

import 'expense.dart';

class ExpenseTotals {
  final int spentMinor;
  final int paidMinor;
  final int unpaidApprovedMinor;
  final int awaitingApprovalMinor;

  const ExpenseTotals({
    this.spentMinor = 0,
    this.paidMinor = 0,
    this.unpaidApprovedMinor = 0,
    this.awaitingApprovalMinor = 0,
  });

  factory ExpenseTotals.fromMap(Map<String, dynamic> m) => ExpenseTotals(
    spentMinor: (m['spentMinor'] as num?)?.toInt() ?? 0,
    paidMinor: (m['paidMinor'] as num?)?.toInt() ?? 0,
    unpaidApprovedMinor: (m['unpaidApprovedMinor'] as num?)?.toInt() ?? 0,
    awaitingApprovalMinor: (m['awaitingApprovalMinor'] as num?)?.toInt() ?? 0,
  );
}

/// One row of a breakdown (a category, a month or a branch).
class ExpenseBucket {
  /// What the row is: a category name, `2026-11`, or a branch name.
  final String label;
  final String key;
  final int count;
  final int totalMinor;
  final int paidMinor;

  const ExpenseBucket({
    required this.label,
    required this.key,
    required this.count,
    required this.totalMinor,
    required this.paidMinor,
  });

  factory ExpenseBucket.fromMap(
    Map<String, dynamic> m, {
    required String keyField,
    String? labelField,
  }) => ExpenseBucket(
    key: (m[keyField] as String?) ?? '',
    label: (m[labelField ?? keyField] as String?) ?? '',
    count: (m['count'] as num?)?.toInt() ?? 0,
    totalMinor: (m['totalMinor'] as num?)?.toInt() ?? 0,
    paidMinor: (m['paidMinor'] as num?)?.toInt() ?? 0,
  );
}

class ExpenseReport {
  final String currency;
  final String fromDate;
  final String toDate;

  /// `SCHOOL` (every branch) or `BRANCH`.
  final String scope;
  final int rows;

  /// True when the range held more expenses than one report reads; the
  /// numbers then cover only part of it and the page says so.
  final bool truncated;
  final ExpenseTotals totals;
  final Map<ExpenseStatus, ({int count, int totalMinor})> byStatus;
  final List<ExpenseBucket> byCategory;
  final List<ExpenseBucket> byMonth;
  final List<ExpenseBucket> byBranch;

  const ExpenseReport({
    required this.currency,
    required this.fromDate,
    required this.toDate,
    required this.scope,
    required this.rows,
    required this.truncated,
    required this.totals,
    required this.byStatus,
    required this.byCategory,
    required this.byMonth,
    required this.byBranch,
  });

  factory ExpenseReport.fromMap(Map<String, dynamic> m) {
    List<ExpenseBucket> buckets(String field, String key, [String? label]) => [
      for (final b in (m[field] as List? ?? const []))
        ExpenseBucket.fromMap(
          Map<String, dynamic>.from(b as Map),
          keyField: key,
          labelField: label,
        ),
    ];
    final status = <ExpenseStatus, ({int count, int totalMinor})>{};
    final raw = (m['byStatus'] as Map?) ?? const {};
    for (final s in ExpenseStatus.values) {
      final v = raw[s.wire];
      status[s] = v is Map
          ? (
              count: (v['count'] as num?)?.toInt() ?? 0,
              totalMinor: (v['totalMinor'] as num?)?.toInt() ?? 0,
            )
          : (count: 0, totalMinor: 0);
    }
    return ExpenseReport(
      currency: (m['currency'] as String?) ?? '',
      fromDate: (m['fromDate'] as String?) ?? '',
      toDate: (m['toDate'] as String?) ?? '',
      scope: (m['scope'] as String?) ?? 'BRANCH',
      rows: (m['rows'] as num?)?.toInt() ?? 0,
      truncated: m['truncated'] == true,
      totals: ExpenseTotals.fromMap(
        Map<String, dynamic>.from((m['totals'] as Map?) ?? const {}),
      ),
      byStatus: status,
      byCategory: buckets('byCategory', 'categoryId', 'name'),
      byMonth: buckets('byMonth', 'month'),
      byBranch: buckets('byBranch', 'branchId', 'name'),
    );
  }

  bool get isEmpty => rows == 0;
  bool get wholeSchool => scope == 'SCHOOL';
}

/// The date ranges the report page offers, as school-day keys (pure, so the
/// edges of a month and a year are unit-tested).
abstract final class ExpenseRanges {
  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The 1st of [today]'s month to [today].
  static ({String from, String to}) thisMonth(DateTime today) =>
      (from: _key(DateTime(today.year, today.month)), to: _key(today));

  /// The whole of the month before [today]'s.
  static ({String from, String to}) lastMonth(DateTime today) {
    final first = DateTime(today.year, today.month - 1);
    final last = DateTime(today.year, today.month, 0);
    return (from: _key(first), to: _key(last));
  }

  /// 1 January of [today]'s year to [today].
  static ({String from, String to}) thisYear(DateTime today) =>
      (from: _key(DateTime(today.year)), to: _key(today));

  /// The 30 days up to and including [today].
  static ({String from, String to}) last30Days(DateTime today) => (
    from: _key(DateTime(today.year, today.month, today.day - 29)),
    to: _key(today),
  );

  /// A plain-words problem with a custom range, or null when it is fine.
  static String? problem(String from, String to, String todayKey) {
    if (from.isEmpty || to.isEmpty) {
      return 'Choose both dates.';
    }
    if (from.compareTo(to) > 0) {
      return 'The start date is after the end date.';
    }
    if (to.compareTo(todayKey) > 0) {
      return 'The end date cannot be in the future.';
    }
    final days = DateTime.parse(to).difference(DateTime.parse(from)).inDays;
    if (days >= 366) {
      return 'Choose a range of at most a year.';
    }
    return null;
  }
}
