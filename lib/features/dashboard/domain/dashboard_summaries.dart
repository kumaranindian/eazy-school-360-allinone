import '../../attendance/domain/attendance_day.dart';
import '../../attendance/domain/attendance_tally.dart';
import '../../fees/domain/fee_summary.dart';

/// Today's student attendance across the branch, built from the registers
/// ([AttendanceDay] documents) that already carry maintained counts - no
/// per-student reads.
///
/// Business rules kept from the attendance module:
/// * a student who has no mark is **not marked**, never "absent";
/// * late and half-day students are present (they attended), so they count in
///   [present];
/// * the attendance percentage follows the attendance reports
///   ([AttendanceTally.percentage]): attended ÷ **marked** students, with a
///   half day weighted 0.5 (DASH-01-DEF-02); students not marked yet are not
///   in the denominator, they are shown as "Not marked".
class AttendanceToday {
  final int expected;
  final int present;
  final int absent;
  final int marked;
  final int registersTaken;

  /// Attended students weighted as in the reports (half day 0.5). Defaults
  /// to [present] (no half days).
  final double? _attended;

  const AttendanceToday({
    required this.expected,
    required this.present,
    required this.absent,
    required this.marked,
    required this.registersTaken,
    double? attended,
  }) : _attended = attended;

  double get attended => _attended ?? present.toDouble();

  /// Attendance of the marked students, 0-1 (0 when nobody is marked).
  double get attendanceRate =>
      marked <= 0 ? 0 : (attended / marked).clamp(0, 1).toDouble();

  int get attendancePercent => (attendanceRate * 100).round();

  /// Students without a mark yet (never negative if the data disagrees).
  int get notMarked => (expected - marked).clamp(0, expected);

  /// Nothing has been recorded today.
  bool get isEmpty => registersTaken == 0 || marked == 0;

  /// Share of students whose attendance is recorded, 0-1.
  double get completion => expected <= 0 ? 0 : (marked / expected).clamp(0, 1);

  int get completionPercent => (completion * 100).round();

  factory AttendanceToday.from({
    required int expectedStudents,
    required Iterable<AttendanceDay> registers,
  }) {
    var total = const AttendanceTally();
    var taken = 0;
    for (final d in registers) {
      final t = d.tally;
      if (t.marked == 0) continue; // an opened, still empty register
      taken++;
      total = total + t;
    }
    return AttendanceToday(
      expected: expectedStudents,
      present: total.present + total.late + total.halfDay,
      absent: total.absent,
      marked: total.marked,
      registersTaken: taken,
      attended: total.attendedDays,
    );
  }
}

/// The fee card: what was collected this month (ACTIVE payments; reversed
/// ones are already excluded by the payment report) next to the academic
/// year's outstanding balance and collection rate - both from the existing
/// fee report definitions, so no new financial arithmetic.
class FeeMonthCard {
  final int collectedThisMonthMinor;
  final int outstandingMinor;
  final double? collectionRatePercent;
  final int invoiceCount;

  const FeeMonthCard({
    required this.collectedThisMonthMinor,
    required this.outstandingMinor,
    required this.collectionRatePercent,
    required this.invoiceCount,
  });

  factory FeeMonthCard.from({
    required CollectionSummary month,
    required FeeSummary year,
  }) => FeeMonthCard(
    collectedThisMonthMinor: month.collectedMinor,
    outstandingMinor: year.outstandingMinor,
    collectionRatePercent: year.collectionRate,
    invoiceCount: year.invoiceCount,
  );

  bool get hasInvoices => invoiceCount > 0;

  /// 0-1 for the progress bar.
  double get progress =>
      ((collectionRatePercent ?? 0) / 100).clamp(0.0, 1.0).toDouble();
}
