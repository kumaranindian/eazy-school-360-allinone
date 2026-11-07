import '../../attendance/domain/attendance_day.dart';
import '../../fees/domain/fee_summary.dart';

/// Today's student attendance across the branch, built from the registers
/// ([AttendanceDay] documents) that already carry maintained counts - no
/// per-student reads.
///
/// Business rules kept from the attendance module:
/// * a student who has no mark is **not marked**, never "absent";
/// * late and half-day students are present (they attended), so they count in
///   [present];
/// * the denominator is the branch's active students ([expected]).
class AttendanceToday {
  final int expected;
  final int present;
  final int absent;
  final int marked;
  final int registersTaken;

  const AttendanceToday({
    required this.expected,
    required this.present,
    required this.absent,
    required this.marked,
    required this.registersTaken,
  });

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
    var present = 0;
    var absent = 0;
    var marked = 0;
    var taken = 0;
    for (final d in registers) {
      final t = d.tally;
      if (t.marked == 0) continue; // an opened, still empty register
      taken++;
      present += t.present + t.late + t.halfDay;
      absent += t.absent;
      marked += t.marked;
    }
    return AttendanceToday(
      expected: expectedStudents,
      present: present,
      absent: absent,
      marked: marked,
      registersTaken: taken,
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
