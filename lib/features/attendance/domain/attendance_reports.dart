import 'attendance_csv.dart';
import 'attendance_status.dart';
import 'attendance_tally.dart';

/// One line of a per-person summary table.
class AttendanceSummaryRow {
  final String subjectId;
  final String name;
  final String? detail;
  final AttendanceTally tally;

  const AttendanceSummaryRow({
    required this.subjectId,
    required this.name,
    this.detail,
    required this.tally,
  });
}

/// Pure aggregation + export for the report screens.
abstract final class AttendanceReports {
  /// Tallies statuses per subject (student or staff) over whatever records
  /// were fetched — the caller fetches one academic year's period, so a
  /// percentage never mixes years.
  static Map<String, AttendanceTally> tallyBySubject(
    Iterable<({String subjectId, AttendanceStatus status})> records,
  ) {
    final grouped = <String, List<AttendanceStatus>>{};
    for (final r in records) {
      grouped.putIfAbsent(r.subjectId, () => []).add(r.status);
    }
    return {
      for (final e in grouped.entries) e.key: AttendanceTally.of(e.value),
    };
  }

  static AttendanceTally total(Iterable<AttendanceSummaryRow> rows) =>
      rows.fold(const AttendanceTally(), (sum, r) => sum + r.tally);

  static String percentLabel(AttendanceTally tally) => tally.percentage == null
      ? '—'
      : '${tally.percentage!.toStringAsFixed(1)}%';

  static const summaryHeader = [
    'Name',
    'Detail',
    'Present',
    'Absent',
    'Late',
    'Half day',
    'Days marked',
    'Attendance %',
  ];

  /// A summary table as CSV. [periodLabel] is repeated on no row — put it in
  /// the file name; every cell here is data. Names/details are sanitized
  /// against spreadsheet formula injection by [AttendanceCsv].
  static String summaryCsv(Iterable<AttendanceSummaryRow> rows) {
    return AttendanceCsv.encode(
      summaryHeader,
      rows.map(
        (r) => [
          r.name,
          r.detail ?? '',
          r.tally.present,
          r.tally.absent,
          r.tally.late,
          r.tally.halfDay,
          r.tally.marked,
          r.tally.percentage == null
              ? ''
              : double.parse(r.tally.percentage!.toStringAsFixed(2)),
        ],
      ),
    );
  }

  /// Day-by-day records of one person as CSV.
  static String dailyCsv(
    String name,
    Iterable<({String dateKey, AttendanceStatus status, String? remarks})> days,
  ) {
    return AttendanceCsv.encode(
      ['Name', 'Date', 'Status', 'Remarks'],
      days.map((d) => [name, d.dateKey, d.status.displayName, d.remarks ?? '']),
    );
  }
}
