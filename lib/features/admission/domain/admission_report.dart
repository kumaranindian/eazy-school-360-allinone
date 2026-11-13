import '../../attendance/domain/attendance_csv.dart';
import 'admission_status.dart';

/// One row of a breakdown: how many enquiries, how many became students.
class ReportRow {
  final String key;
  final String label;
  final int count;
  final int confirmed;
  final double ratePercent;
  const ReportRow({
    required this.key,
    required this.label,
    required this.count,
    required this.confirmed,
    required this.ratePercent,
  });
}

class FeeCategoryTotal {
  final String category;
  final int amountMinor;
  final int netPaidMinor;
  final int balanceMinor;
  const FeeCategoryTotal(
    this.category,
    this.amountMinor,
    this.netPaidMinor,
    this.balanceMinor,
  );
}

/// The aggregates of `getAdmissionReport` (`functions/admission_reports.js`).
/// Only counts, rates and money totals: no personal data.
class AdmissionReport {
  final int total;
  final Map<AdmissionStatus, int> byStatus;
  final int confirmed;
  final double conversionPercent;
  final List<ReportRow> bySource;
  final List<ReportRow> byClass;
  final List<ReportRow> byAssignee;
  final List<ReportRow> byBranch;
  final List<({String month, int count, int confirmed})> byMonth;
  final int lostTotal;
  final Map<String, int> lostByStatus;
  final List<({String reason, int count})> lostReasons;
  final int followUpsTotal;
  final int followUpsCompleted;
  final int followUpsOpen;
  final int followUpsOverdue;
  final double followUpCompletionPercent;
  final String currency;
  final int feeAmountMinor;
  final int feeNetPaidMinor;
  final int feeBalanceMinor;
  final List<FeeCategoryTotal> feeCategories;
  final bool truncated;
  final bool schoolWide;

  const AdmissionReport({
    required this.total,
    required this.byStatus,
    required this.confirmed,
    required this.conversionPercent,
    required this.bySource,
    required this.byClass,
    required this.byAssignee,
    required this.byBranch,
    required this.byMonth,
    required this.lostTotal,
    required this.lostByStatus,
    required this.lostReasons,
    required this.followUpsTotal,
    required this.followUpsCompleted,
    required this.followUpsOpen,
    required this.followUpsOverdue,
    required this.followUpCompletionPercent,
    required this.currency,
    required this.feeAmountMinor,
    required this.feeNetPaidMinor,
    required this.feeBalanceMinor,
    required this.feeCategories,
    required this.truncated,
    required this.schoolWide,
  });

  static int _i(Object? v) => v is num ? v.toInt() : 0;
  static double _d(Object? v) => v is num ? v.toDouble() : 0;
  static List<Map<String, dynamic>> _list(Object? v) => [
    for (final e in (v is List ? v : const []))
      if (e is Map) e.cast<String, dynamic>(),
  ];

  /// The server returns `classNames` (id → name) with the report.
  factory AdmissionReport.fromMap(Map<String, dynamic> d) {
    final classNames = {
      for (final e in ((d['classNames'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    ReportRow row(
      Map<String, dynamic> m,
      String keyField,
      String Function(Map<String, dynamic>) label,
    ) => ReportRow(
      key: '${m[keyField] ?? ''}',
      label: label(m),
      count: _i(m['count']),
      confirmed: _i(m['confirmed']),
      ratePercent: _d(m['ratePercent']),
    );
    final conv = (d['conversion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lost = (d['lost'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fu = (d['followUps'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fees = (d['fees'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AdmissionReport(
      total: _i(d['total']),
      byStatus: {
        for (final e in ((d['byStatus'] as Map?) ?? const {}).entries)
          if (AdmissionStatus.tryParse(e.key as String) != null)
            AdmissionStatus.tryParse(e.key as String)!: _i(e.value),
      },
      confirmed: _i(conv['confirmed']),
      conversionPercent: _d(conv['ratePercent']),
      bySource: [
        for (final m in _list(d['bySource']))
          row(m, 'source', (x) => '${x['source']}'),
      ],
      byClass: [
        for (final m in _list(d['byClass']))
          row(
            m,
            'classId',
            (x) => classNames['${x['classId']}'] ?? 'Class ${x['classId']}',
          ),
      ],
      byAssignee: [
        for (final m in _list(d['byAssignee']))
          row(m, 'userId', (x) => '${x['name']}'),
      ],
      byBranch: [
        for (final m in _list(d['byBranch']))
          row(m, 'branchId', (x) => '${x['name']}'),
      ],
      byMonth: [
        for (final m in _list(d['byMonth']))
          (
            month: '${m['month']}',
            count: _i(m['count']),
            confirmed: _i(m['confirmed']),
          ),
      ],
      lostTotal: _i(lost['total']),
      lostByStatus: {
        for (final k in const ['NOT_INTERESTED', 'REJECTED', 'WITHDRAWN'])
          k: _i(lost[k]),
      },
      lostReasons: [
        for (final m in _list(lost['reasons']))
          (reason: '${m['reason']}', count: _i(m['count'])),
      ],
      followUpsTotal: _i(fu['total']),
      followUpsCompleted: _i(fu['completed']),
      followUpsOpen: _i(fu['open']),
      followUpsOverdue: _i(fu['overdueOpen']),
      followUpCompletionPercent: _d(fu['completionRatePercent']),
      currency: fees['currency'] as String? ?? 'INR',
      feeAmountMinor: _i(fees['amountMinor']),
      feeNetPaidMinor: _i(fees['netPaidMinor']),
      feeBalanceMinor: _i(fees['balanceMinor']),
      feeCategories: [
        for (final m in _list(fees['byCategory']))
          FeeCategoryTotal(
            '${m['category']}',
            _i(m['amountMinor']),
            _i(m['netPaidMinor']),
            _i(m['balanceMinor']),
          ),
      ],
      truncated: d['truncated'] == true,
      schoolWide: d['scope'] == 'SCHOOL',
    );
  }

  /// A flat CSV: one row per figure, so it opens as a simple table. Text
  /// cells go through the same formula-injection guard as the attendance CSV.
  String toCsv({String Function(int minor)? money}) {
    String m(int v) => money == null ? '$v' : money(v);
    final rows = <List<Object?>>[
      ['Summary', 'Enquiries', total, '', ''],
      ['Summary', 'Admissions confirmed', confirmed, '', conversionPercent],
      for (final e in byStatus.entries)
        ['Status', e.key.label, e.value, '', ''],
      for (final r in bySource)
        ['Source', r.label, r.count, r.confirmed, r.ratePercent],
      for (final r in byClass)
        ['Class', r.label, r.count, r.confirmed, r.ratePercent],
      for (final r in byAssignee)
        ['Assigned to', r.label, r.count, r.confirmed, r.ratePercent],
      for (final r in byBranch)
        ['Branch', r.label, r.count, r.confirmed, r.ratePercent],
      for (final r in byMonth) ['Month', r.month, r.count, r.confirmed, ''],
      ['Lost', 'Total', lostTotal, '', ''],
      for (final e in lostByStatus.entries) ['Lost', e.key, e.value, '', ''],
      for (final r in lostReasons) ['Lost reason', r.reason, r.count, '', ''],
      ['Follow-ups', 'Total', followUpsTotal, '', ''],
      [
        'Follow-ups',
        'Completed',
        followUpsCompleted,
        '',
        followUpCompletionPercent,
      ],
      ['Follow-ups', 'Open', followUpsOpen, '', ''],
      ['Follow-ups', 'Overdue', followUpsOverdue, '', ''],
      ['Fees', 'Asked', m(feeAmountMinor), '', ''],
      ['Fees', 'Collected (net of refunds)', m(feeNetPaidMinor), '', ''],
      ['Fees', 'Balance due', m(feeBalanceMinor), '', ''],
      for (final c in feeCategories)
        [
          'Fees',
          c.category,
          m(c.amountMinor),
          m(c.netPaidMinor),
          m(c.balanceMinor),
        ],
    ];
    return AttendanceCsv.encode([
      'Section',
      'Item',
      'Count / amount',
      'Confirmed / collected',
      'Rate % / balance',
    ], rows);
  }
}
