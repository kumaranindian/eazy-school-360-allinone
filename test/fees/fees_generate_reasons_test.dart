import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/fees/domain/billing_period.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_planners.dart';
import 'package:eazy_school_360/features/fees/domain/fee_structure.dart';
import 'package:eazy_school_360/features/fees/domain/invoice.dart';
import 'package:eazy_school_360/features/fees/domain/student_fee_assignment.dart';
import 'package:eazy_school_360/features/fees/presentation/widgets/student_all_years_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeeStructure _fee(
  String code, {
  FeeFrequency frequency = FeeFrequency.monthly,
  ActivationStatus status = ActivationStatus.active,
  String? from,
}) => FeeStructure(
  structureId: FeeStructure.idFor('y26', code),
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y26',
  code: code,
  name: code,
  category: FeeCategory.tuition,
  frequency: frequency,
  amountMinor: 100000,
  effectiveFromKey: from,
  status: status,
);

StudentFeeAssignment _assign(FeeStructure f) => StudentFeeAssignment(
  assignmentId: StudentFeeAssignment.idFor('1', f.structureId),
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y26',
  studentId: '1',
  structureId: f.structureId,
  structureName: f.name,
  classId: 'c5',
  concessionType: ConcessionType.none,
  concessionValue: 0,
  isActive: true,
);

const _student = FeeStudent(
  studentId: '1',
  name: 'Asha',
  admissionNumber: 'ADM-1',
  classId: 'c5',
  className: 'Class 5',
  sectionId: 'a',
  sectionName: 'A',
  isEnrolled: true,
);

String _why(
  FeeStructure f, {
  BillingPeriod? period,
  String issue = '2026-06-01',
}) {
  final plan = InvoicePlanner.plan(
    students: const [_student],
    assignmentsByStudent: {
      '1': [BillableAssignment(_assign(f), f)],
    },
    period: period ?? BillingPeriod.monthly(2026, 6),
    academicYearId: 'y26',
    issueDateKey: issue,
    existingChargeIds: const {},
    existingInvoiceIds: const {},
    addDays: (k, d) => k,
  );
  expect(plan.proposals, isEmpty);
  return plan.skipped.single.reason;
}

Invoice _inv(String year, String yearName, int payable, int paid) => Invoice(
  invoiceId: 'i-$year',
  schoolId: 's',
  branchId: 'b',
  invoiceNumber: 'INV-1',
  numberSeq: 1,
  studentId: '1',
  studentName: 'Asha',
  admissionNumber: 'ADM-1',
  academicYearId: year,
  academicYearName: yearName,
  classId: 'c5',
  className: 'Class 5',
  sectionId: 'a',
  sectionName: 'A',
  periodKind: FeeFrequency.monthly,
  periodKey: 'M-2025-06',
  periodLabel: 'June',
  issueDateKey: '2025-06-01',
  dueDateKey: '2025-06-16',
  lines: const [],
  subtotalMinor: payable,
  discountMinor: 0,
  payableMinor: payable,
  waivedMinor: 0,
  paidMinor: paid,
  balanceMinor: payable - paid,
  status: paid == 0 ? InvoiceStatus.issued : InvoiceStatus.partiallyPaid,
  schoolName: 'S',
  branchName: 'B',
);

void main() {
  group('nothing-to-invoice explains why', () {
    test('wrong frequency names the fee and both frequencies', () {
      final r = _why(_fee('TUITION', frequency: FeeFrequency.quarterly));
      expect(r, contains('"TUITION" is quarterly, not monthly'));
    });

    test('inactive structure', () {
      expect(
        _why(_fee('BUS', status: ActivationStatus.inactive)),
        contains('"BUS" is inactive'),
      );
    });

    test('not yet effective on the issue date', () {
      expect(
        _why(_fee('LAB', from: '2027-01-01')),
        contains('"LAB" is not effective on the issue date'),
      );
    });
  });

  testWidgets('all-years ledger flags dues carried from earlier years', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudentAllYearsLedger(
              currency: 'INR',
              selectedYearId: 'y26',
              future: Future.value([
                _inv('y25', '2025-26', 500000, 100000), // 4,000 pending
                _inv('y26', '2026-27', 200000, 0), // 2,000 pending
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('pending from earlier years'), findsOneWidget);
    // One row per year plus the total.
    expect(find.text('2025-26'), findsOneWidget);
    expect(find.text('2026-27'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });
}
