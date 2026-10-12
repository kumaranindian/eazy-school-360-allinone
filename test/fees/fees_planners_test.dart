import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/fees/domain/billing_period.dart';
import 'package:eazy_school_360/features/fees/domain/fee_dates.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_planners.dart';
import 'package:eazy_school_360/features/fees/domain/fee_structure.dart';
import 'package:eazy_school_360/features/fees/domain/student_fee_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

FeeStudent _student(
  String id, {
  bool enrolled = true,
  String classId = 'c5',
  String? sectionId = 'a',
}) => FeeStudent(
  studentId: id,
  name: 'Student $id',
  admissionNumber: 'ADM-$id',
  classId: classId,
  className: 'Class 5',
  sectionId: sectionId,
  sectionName: 'A',
  isEnrolled: enrolled,
);

FeeStructure _fee(
  String code, {
  int amount = 100000,
  FeeFrequency frequency = FeeFrequency.monthly,
  String? classId,
  String? sectionId,
  bool optional = false,
  ActivationStatus status = ActivationStatus.active,
  String year = 'y26',
  String? from,
  String? to,
  int dueDays = 15,
}) {
  return FeeStructure(
    structureId: FeeStructure.idFor(year, code),
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: year,
    code: code,
    name: code,
    category: FeeCategory.tuition,
    frequency: frequency,
    amountMinor: amount,
    classId: classId,
    sectionId: sectionId,
    isOptional: optional,
    effectiveFromKey: from,
    effectiveToKey: to,
    dueOffsetDays: dueDays,
    status: status,
  );
}

StudentFeeAssignment _assign(
  String studentId,
  FeeStructure s, {
  ConcessionType type = ConcessionType.none,
  int value = 0,
  bool active = true,
  String year = 'y26',
}) {
  return StudentFeeAssignment(
    assignmentId: StudentFeeAssignment.idFor(studentId, s.structureId),
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: year,
    studentId: studentId,
    structureId: s.structureId,
    structureName: s.name,
    classId: 'c5',
    concessionType: type,
    concessionValue: value,
    concessionReason: type == ConcessionType.none ? null : 'approved',
    isActive: active,
  );
}

InvoicePlan _plan({
  required List<FeeStudent> students,
  required Map<String, List<BillableAssignment>> assignments,
  BillingPeriod? period,
  String issue = '2026-06-01',
  Set<String> charges = const {},
  Set<String> invoices = const {},
  String? dueOverride,
}) {
  return InvoicePlanner.plan(
    students: students,
    assignmentsByStudent: assignments,
    period: period ?? BillingPeriod.monthly(2026, 6),
    academicYearId: 'y26',
    issueDateKey: issue,
    dueDateKeyOverride: dueOverride,
    existingChargeIds: charges,
    existingInvoiceIds: invoices,
    addDays: FeeDates.addDays,
  );
}

void main() {
  group('AssignmentPlanner — who gets which fee head', () {
    test('assigns every applicable fee to every enrolled student', () {
      final tuition = _fee('TUITION');
      final plan = AssignmentPlanner.plan(
        students: [_student('1'), _student('2')],
        structures: [tuition],
        academicYearId: 'y26',
        existingAssignmentIds: {},
      );
      expect(plan.toCreate, hasLength(2));
      expect(plan.skipped, isEmpty);
      expect(plan.totalMinor, 200000);
      expect(plan.breakdown['TUITION'], (students: 2, totalMinor: 200000));
    });

    test('does NOT charge a student who is not enrolled', () {
      final plan = AssignmentPlanner.plan(
        students: [_student('1'), _student('2', enrolled: false)],
        structures: [_fee('TUITION')],
        academicYearId: 'y26',
        existingAssignmentIds: {},
      );
      expect(plan.toCreate.map((p) => p.student.studentId), ['1']);
      expect(plan.skipped.single.reason, contains('Not currently enrolled'));
    });

    test(
      'prevents duplicates: an existing assignment for the same student and fee head is skipped',
      () {
        final tuition = _fee('TUITION');
        final existing = {StudentFeeAssignment.idFor('1', tuition.structureId)};
        final plan = AssignmentPlanner.plan(
          students: [_student('1'), _student('2')],
          structures: [tuition],
          academicYearId: 'y26',
          existingAssignmentIds: existing,
        );
        expect(plan.toCreate.map((p) => p.student.studentId), ['2']);
        expect(plan.skipped.single.reason, contains('already assigned'));
      },
    );

    test(
      'running the same plan again after applying it creates nothing new (idempotent)',
      () {
        final tuition = _fee('TUITION');
        final first = AssignmentPlanner.plan(
          students: [_student('1'), _student('2')],
          structures: [tuition],
          academicYearId: 'y26',
          existingAssignmentIds: {},
        );
        final created = {
          for (final p in first.toCreate)
            StudentFeeAssignment.idFor(
              p.student.studentId,
              p.structure.structureId,
            ),
        };
        final second = AssignmentPlanner.plan(
          students: [_student('1'), _student('2')],
          structures: [tuition],
          academicYearId: 'y26',
          existingAssignmentIds: created,
        );
        expect(second.toCreate, isEmpty);
      },
    );

    test('respects class and section scope', () {
      final plan = AssignmentPlanner.plan(
        students: [
          _student('1'),
          _student('2', classId: 'c6'),
          _student('3', sectionId: 'b'),
        ],
        structures: [_fee('C5A', classId: 'c5', sectionId: 'a')],
        academicYearId: 'y26',
        existingAssignmentIds: {},
      );
      expect(plan.toCreate.map((p) => p.student.studentId), ['1']);
      expect(plan.skipped, hasLength(2));
    });

    test('skips inactive fees and fees of another academic year', () {
      final plan = AssignmentPlanner.plan(
        students: [_student('1')],
        structures: [
          _fee('OLD', status: ActivationStatus.inactive),
          _fee('NEXT', year: 'y27'),
          _fee('OK'),
        ],
        academicYearId: 'y26',
        existingAssignmentIds: {},
      );
      expect(plan.toCreate.map((p) => p.structure.code), ['OK']);
      expect(
        plan.skipped.map((s) => s.reason).join(),
        allOf(contains('inactive'), contains('different academic year')),
      );
    });

    test('a class-wide plan counts across fee heads', () {
      final plan = AssignmentPlanner.plan(
        students: [_student('1'), _student('2'), _student('3')],
        structures: [
          _fee('TUITION', amount: 100000),
          _fee('BUS', amount: 25000, optional: true),
        ],
        academicYearId: 'y26',
        existingAssignmentIds: {},
      );
      expect(plan.toCreate, hasLength(6));
      expect(plan.totalMinor, 3 * 100000 + 3 * 25000);
      expect(plan.breakdown.keys, containsAll(['TUITION', 'BUS']));
    });
  });

  group('InvoicePlanner — who is billed, for what, and why not', () {
    final tuition = _fee('TUITION', amount: 150000);
    final transport = _fee('BUS', amount: 25000, dueDays: 30);

    Map<String, List<BillableAssignment>> assignments(
      Map<String, List<(FeeStructure, StudentFeeAssignment)>> m,
    ) => {
      for (final e in m.entries)
        e.key: [for (final p in e.value) BillableAssignment(p.$2, p.$1)],
    };

    test(
      'one invoice per student with a line per due fee head; totals add up',
      () {
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (tuition, _assign('1', tuition)),
              (transport, _assign('1', transport)),
            ],
          }),
        );
        final p = plan.proposals.single;
        expect(p.invoiceId, '1__y26__M-2026-06');
        expect(p.lines.map((l) => l.name), ['TUITION', 'BUS']);
        expect(p.subtotalMinor, 175000);
        expect(p.discountMinor, 0);
        expect(p.payableMinor, 175000);
        expect(plan.payableMinor, 175000);
      },
    );

    test('a concession is applied per line and frozen into it', () {
      final plan = _plan(
        students: [_student('1')],
        assignments: assignments({
          '1': [
            (
              tuition,
              _assign('1', tuition, type: ConcessionType.percent, value: 2500),
            ),
          ],
        }),
      );
      final line = plan.proposals.single.lines.single;
      expect(
        (line.amountMinor, line.discountMinor, line.netMinor),
        (150000, 37500, 112500),
      );
      expect(line.concessionNote, 'approved');
      expect(plan.discountMinor, 37500);
      expect(plan.payableMinor, 112500);
    });

    test(
      'concession arithmetic: discount + net == amount, for every line, with half-up rounding',
      () {
        final odd = _fee('ODD', amount: 100005);
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (
                odd,
                _assign('1', odd, type: ConcessionType.percent, value: 1000),
              ),
            ],
          }),
        );
        final line = plan.proposals.single.lines.single;
        expect(line.discountMinor, 10001);
        expect(line.discountMinor + line.netMinor, line.amountMinor);
      },
    );

    test(
      'a scholarship (100%) leaves nothing to bill and the student is skipped, not invoiced for zero',
      () {
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (
                tuition,
                _assign(
                  '1',
                  tuition,
                  type: ConcessionType.percent,
                  value: 10000,
                ),
              ),
            ],
          }),
        );
        expect(plan.proposals, isEmpty);
        expect(plan.skipped.single.reason, contains('Fully concessed'));
      },
    );

    test('students who are not enrolled are never billed', () {
      final plan = _plan(
        students: [_student('1', enrolled: false)],
        assignments: assignments({
          '1': [(tuition, _assign('1', tuition))],
        }),
      );
      expect(plan.proposals, isEmpty);
      expect(plan.skipped.single.reason, contains('Not currently enrolled'));
    });

    test('students with no assignments are reported, not silently dropped', () {
      final plan = _plan(students: [_student('1')], assignments: {});
      expect(plan.skipped.single.reason, 'No fees assigned');
    });

    test(
      'only fees of the billed period kind appear: a quarterly fee is not on a monthly invoice',
      () {
        final quarterly = _fee(
          'Q',
          frequency: FeeFrequency.quarterly,
          amount: 300000,
        );
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (tuition, _assign('1', tuition)),
              (quarterly, _assign('1', quarterly)),
            ],
          }),
        );
        expect(plan.proposals.single.lines.map((l) => l.name), ['TUITION']);

        final quarterPlan = _plan(
          students: [_student('1')],
          period: BillingPeriod.quarterly(2026, 2),
          assignments: assignments({
            '1': [
              (tuition, _assign('1', tuition)),
              (quarterly, _assign('1', quarterly)),
            ],
          }),
        );
        expect(quarterPlan.proposals.single.lines.map((l) => l.name), ['Q']);
      },
    );

    test(
      'a cancelled assignment, an inactive fee and a fee outside its effective window are not billed',
      () {
        final inactive = _fee('INACTIVE', status: ActivationStatus.inactive);
        final future = _fee('FUTURE', from: '2026-09-01');
        final expired = _fee('EXPIRED', to: '2026-05-31');
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (tuition, _assign('1', tuition, active: false)),
              (inactive, _assign('1', inactive)),
              (future, _assign('1', future)),
              (expired, _assign('1', expired)),
            ],
          }),
        );
        expect(plan.proposals, isEmpty);
      },
    );

    test(
      'a fee whose structure was removed is skipped rather than crashing',
      () {
        final plan = _plan(
          students: [_student('1')],
          assignments: {
            '1': [BillableAssignment(_assign('1', tuition), null)],
          },
        );
        expect(plan.proposals, isEmpty);
      },
    );

    test('an assignment from a different academic year is ignored', () {
      final plan = _plan(
        students: [_student('1')],
        assignments: assignments({
          '1': [(tuition, _assign('1', tuition, year: 'y25'))],
        }),
      );
      expect(plan.proposals, isEmpty);
    });

    test(
      'DUPLICATE PREVENTION: a line already charged for this period is not billed again',
      () {
        final a = _assign('1', tuition);
        final charge = '${a.assignmentId}__M-2026-06';
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [(tuition, a)],
          }),
          charges: {charge},
        );
        expect(plan.proposals, isEmpty);
      },
    );

    test(
      'a different month for the same fee is billed (recurring fees repeat)',
      () {
        final a = _assign('1', tuition);
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [(tuition, a)],
          }),
          period: BillingPeriod.monthly(2026, 7),
          charges: {'${a.assignmentId}__M-2026-06'},
        );
        expect(plan.proposals, hasLength(1));
      },
    );

    test(
      'IDEMPOTENCY: a student whose invoice for this period exists is skipped — re-running a bulk run creates nothing',
      () {
        final plan = _plan(
          students: [_student('1'), _student('2')],
          assignments: assignments({
            '1': [(tuition, _assign('1', tuition))],
            '2': [(tuition, _assign('2', tuition))],
          }),
          invoices: {'1__y26__M-2026-06'},
        );
        expect(plan.proposals.map((p) => p.student.studentId), ['2']);
        expect(plan.skipped.single.reason, contains('Already invoiced'));
      },
    );

    test('a one-time fee is charged once, whatever the label of the run', () {
      final admission = _fee(
        'ADM',
        frequency: FeeFrequency.oneTime,
        amount: 500000,
      );
      final a = _assign('1', admission);
      final first = _plan(
        students: [_student('1')],
        assignments: assignments({
          '1': [(admission, a)],
        }),
        period: BillingPeriod.oneTime('Admission 2026'),
      );
      expect(
        first.proposals.single.lines.single.chargeId,
        '${a.assignmentId}__ONCE',
      );

      // billed already under one label ⇒ a run with a different label finds the same charge lock
      final second = _plan(
        students: [_student('1')],
        assignments: assignments({
          '1': [(admission, a)],
        }),
        period: BillingPeriod.oneTime('Re-run'),
        charges: {'${a.assignmentId}__ONCE'},
      );
      expect(second.proposals, isEmpty);
    });

    test('a custom period bills custom-frequency fees once per label', () {
      final term = _fee('TERM', frequency: FeeFrequency.custom, amount: 400000);
      final a = _assign('1', term);
      final plan = _plan(
        students: [_student('1')],
        assignments: assignments({
          '1': [(term, a)],
        }),
        period: BillingPeriod.custom('Term 1'),
      );
      expect(
        plan.proposals.single.lines.single.chargeId,
        '${a.assignmentId}__C-term-1',
      );
    });

    test(
      'due date = issue date + the longest "days until due" among the lines, or an explicit override',
      () {
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [
              (tuition, _assign('1', tuition)),
              (transport, _assign('1', transport)),
            ],
          }),
          issue: '2026-06-01',
        );
        expect(plan.proposals.single.dueDateKey, '2026-07-01');
        final overridden = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [(tuition, _assign('1', tuition))],
          }),
          dueOverride: '2026-06-30',
        );
        expect(overridden.proposals.single.dueDateKey, '2026-06-30');
      },
    );

    test(
      'academic-year boundary: nothing is billed for assignments of another year, and invoice ids carry the year',
      () {
        final plan = _plan(
          students: [_student('1')],
          assignments: assignments({
            '1': [(tuition, _assign('1', tuition))],
          }),
        );
        expect(plan.proposals.single.invoiceId, contains('__y26__'));
      },
    );

    test('a billing run over a whole class totals correctly', () {
      final students = [for (var i = 1; i <= 30; i++) _student('$i')];
      final plan = _plan(
        students: students,
        assignments: {
          for (final s in students)
            s.studentId: [
              BillableAssignment(_assign(s.studentId, tuition), tuition),
            ],
        },
      );
      expect(plan.proposals, hasLength(30));
      expect(plan.payableMinor, 30 * 150000);
      expect(plan.proposals.map((p) => p.invoiceId).toSet(), hasLength(30));
    });
  });
}
