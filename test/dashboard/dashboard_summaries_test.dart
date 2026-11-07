import 'package:eazy_school_360/features/attendance/domain/attendance_day.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_tally.dart';
import 'package:eazy_school_360/features/dashboard/domain/dashboard_summaries.dart';
import 'package:eazy_school_360/features/fees/domain/fee_summary.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceDay _day(AttendanceTally t, {String section = 's'}) => AttendanceDay(
  dayId: 'd$section',
  schoolId: 'sc',
  branchId: 'b',
  academicYearId: 'y',
  classId: 'c',
  sectionId: section,
  dateKey: '2026-08-03',
  status: AttendanceDayStatus.draft,
  tally: t,
);

void main() {
  group('AttendanceToday', () {
    test('students without a mark are "not marked", never absent', () {
      final a = AttendanceToday.from(
        expectedStudents: 100,
        registers: [
          _day(const AttendanceTally(present: 30, absent: 5), section: 'a'),
          _day(const AttendanceTally(present: 20, absent: 5), section: 'b'),
        ],
      );
      expect(a.present, 50);
      expect(a.absent, 10);
      expect(a.marked, 60);
      expect(a.notMarked, 40); // 100 expected - 60 marked
      expect(a.completionPercent, 60);
      expect(a.isEmpty, isFalse);
    });

    test('late and half-day students attended: they count as present', () {
      final a = AttendanceToday.from(
        expectedStudents: 10,
        registers: [
          _day(
            const AttendanceTally(present: 4, late: 2, halfDay: 1, absent: 1),
          ),
        ],
      );
      expect(a.present, 7);
      expect(a.absent, 1);
      expect(a.marked, 8);
    });

    test(
      'a register that was opened but has no marks is not a taken register',
      () {
        final a = AttendanceToday.from(
          expectedStudents: 30,
          registers: [_day(const AttendanceTally(notMarked: 30))],
        );
        expect(a.isEmpty, isTrue);
        expect(a.registersTaken, 0);
        expect(a.notMarked, 30);
        expect(a.completionPercent, 0);
      },
    );

    test('no registers at all is the empty state', () {
      final a = AttendanceToday.from(expectedStudents: 30, registers: const []);
      expect(a.isEmpty, isTrue);
      expect(a.notMarked, 30);
    });

    test('inconsistent data never goes negative or above 100%', () {
      final a = AttendanceToday.from(
        expectedStudents: 5,
        registers: [_day(const AttendanceTally(present: 9))],
      );
      expect(a.notMarked, 0);
      expect(a.completion, 1);
    });

    test('no students: no divide by zero', () {
      final a = AttendanceToday.from(expectedStudents: 0, registers: const []);
      expect(a.completion, 0);
      expect(a.notMarked, 0);
    });
  });

  group('FeeMonthCard', () {
    const year = FeeSummary(
      invoiceCount: 10,
      grossMinor: 1100000,
      discountMinor: 100000,
      payableMinor: 1000000,
      waivedMinor: 0,
      collectedMinor: 600000,
      outstandingMinor: 400000,
      overdueMinor: 100000,
      overdueInvoiceCount: 1,
      partiallyPaidCount: 2,
      paidCount: 4,
    );
    const month = CollectionSummary(
      paymentCount: 3,
      collectedMinor: 250000,
      byMethodMinor: {'CASH': 250000},
      reversedMinor: 0,
      refundedMinor: 0,
    );

    test('uses the existing report numbers without new arithmetic', () {
      final c = FeeMonthCard.from(month: month, year: year);
      expect(c.collectedThisMonthMinor, 250000);
      expect(c.outstandingMinor, 400000);
      expect(c.collectionRatePercent, 60);
      expect(c.progress, closeTo(0.6, 1e-9));
      expect(c.hasInvoices, isTrue);
    });

    test('no invoices: empty state, no rate', () {
      const none = FeeSummary(
        invoiceCount: 0,
        grossMinor: 0,
        discountMinor: 0,
        payableMinor: 0,
        waivedMinor: 0,
        collectedMinor: 0,
        outstandingMinor: 0,
        overdueMinor: 0,
        overdueInvoiceCount: 0,
        partiallyPaidCount: 0,
        paidCount: 0,
      );
      final c = FeeMonthCard.from(month: month, year: none);
      expect(c.hasInvoices, isFalse);
      expect(c.collectionRatePercent, isNull);
      expect(c.progress, 0);
    });
  });
}
