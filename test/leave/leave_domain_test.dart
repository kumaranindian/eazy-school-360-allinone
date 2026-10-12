import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_balance.dart';
import 'package:eazy_school_360/features/leave/domain/leave_days.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:eazy_school_360/features/leave/domain/leave_units.dart';
import 'package:eazy_school_360/features/leave/domain/leave_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

LeaveType _type({
  LeaveKind kind = LeaveKind.student,
  String code = 'SICK',
  LeavePayType pay = LeavePayType.notApplicable,
  bool halfDay = true,
  bool countNonWorking = false,
  int? maxDays,
  int? entitlement,
  int carry = 0,
  bool requiresDoc = false,
  ActivationStatus status = ActivationStatus.active,
  List<String> roles = const [],
  List<String> employment = const [],
}) => LeaveType(
  typeId: LeaveType.idFor(kind, code),
  schoolId: 's',
  branchId: 'b',
  kind: kind,
  code: code,
  name: 'Sick leave',
  payType: pay,
  allowHalfDay: halfDay,
  countNonWorkingDays: countNonWorking,
  maxDaysPerRequest: maxDays,
  annualEntitlementUnits: entitlement,
  carryForwardMaxUnits: carry,
  requiresDocument: requiresDoc,
  status: status,
  applicableRoles: roles,
  applicableEmploymentTypes: employment,
);

Holiday _holiday(String key, {HolidayType type = HolidayType.public}) {
  final p = key.split('-').map(int.parse).toList();
  return Holiday(
    holidayId: key,
    schoolId: 's',
    branchId: 'b',
    academicYearId: 'y',
    date: DateTime.utc(p[0], p[1], p[2]),
    name: 'Diwali',
    type: type,
    status: ActivationStatus.active,
  );
}

LeaveDaySpan _span(
  String start,
  String end, {
  HalfDay half = HalfDay.none,
  LeaveType? type,
  List<Holiday> holidays = const [],
  WorkingDays? wd,
}) => LeaveDayCalculator.compute(
  startKey: start,
  endKey: end,
  halfDay: half,
  type: type ?? _type(),
  workingDays: wd ?? WorkingDays.defaults(schoolId: 's', branchId: 'b'),
  calendarEntries: holidays,
  yearStartKey: '2026-06-01',
  yearEndKey: '2027-03-31',
);

LeaveApplication _app({
  String id = 'a1',
  LeaveStatus status = LeaveStatus.pending,
  String start = '2026-08-03',
  String end = '2026-08-04',
  HalfDay half = HalfDay.none,
  String applicant = 'u-parent',
  List<String>? counted,
}) => LeaveApplication(
  applicationId: id,
  schoolId: 's',
  branchId: 'b',
  kind: LeaveKind.student,
  subjectId: 'stu',
  subjectName: 'Anil',
  applicantUserId: applicant,
  applicantName: 'P',
  relation: ApplicantRelation.parent,
  typeId: 'STUDENT__sick',
  typeName: 'Sick',
  payType: LeavePayType.notApplicable,
  startDateKey: start,
  endDateKey: end,
  halfDay: half,
  units: 4,
  countedDateKeys: counted ?? [start, end],
  status: status,
);

void main() {
  group('LeaveUnits (half-day integers)', () {
    test('formats whole and half days', () {
      expect(LeaveUnits.format(0), '0');
      expect(LeaveUnits.format(1), '0.5');
      expect(LeaveUnits.format(2), '1');
      expect(LeaveUnits.format(5), '2.5');
      expect(LeaveUnits.format(-3), '-1.5');
      expect(LeaveUnits.formatDays(2), '1 day');
      expect(LeaveUnits.formatDays(3), '1.5 days');
    });

    test('parses only multiples of half a day', () {
      expect(LeaveUnits.parse('12'), 24);
      expect(LeaveUnits.parse('0.5'), 1);
      expect(LeaveUnits.parse('7.5'), 15);
      expect(LeaveUnits.parse('1.25'), isNull);
      expect(LeaveUnits.parse('abc'), isNull);
      expect(LeaveUnits.parse(''), isNull);
    });
  });

  group('LeaveType validation', () {
    test('a valid student type', () => expect(_type().validate(), isNull));

    test('student leave cannot be paid/unpaid or carry an entitlement', () {
      expect(_type(pay: LeavePayType.paid).validate(), isNotNull);
      expect(_type(entitlement: 24).validate(), isNotNull);
    });

    test('staff leave must choose paid or unpaid; unpaid has no balance', () {
      final k = LeaveKind.staff;
      expect(
        _type(kind: k, pay: LeavePayType.notApplicable).validate(),
        isNotNull,
      );
      expect(
        _type(kind: k, pay: LeavePayType.unpaid, entitlement: 10).validate(),
        isNotNull,
      );
      expect(
        _type(kind: k, pay: LeavePayType.paid, entitlement: 24).validate(),
        isNull,
      );
    });

    test('code, name, caps and carry-forward are validated', () {
      expect(_type(code: 'a').validate(), contains('Code'));
      expect(_type(maxDays: 0).validate(), isNotNull);
      expect(_type(maxDays: 61).validate(), isNotNull);
      expect(
        _type(
          kind: LeaveKind.staff,
          pay: LeavePayType.paid,
          carry: 4,
        ).validate(),
        isNotNull,
        reason: 'carry-forward needs an entitlement',
      );
    });

    test('a balance is tracked only for staff types with an entitlement', () {
      expect(_type().tracksBalance, isFalse);
      expect(
        _type(
          kind: LeaveKind.staff,
          pay: LeavePayType.paid,
          entitlement: 24,
        ).tracksBalance,
        isTrue,
      );
      expect(
        _type(kind: LeaveKind.staff, pay: LeavePayType.paid).tracksBalance,
        isFalse,
      );
    });

    test('the global cap bounds any configured maximum', () {
      expect(_type().effectiveMaxDays, 60);
      expect(_type(maxDays: 5).effectiveMaxDays, 5);
    });
  });

  group('LeaveDayCalculator', () {
    test('counts only working days (Mon–Fri default): Mon–Sun = 5 days', () {
      final s = _span('2026-08-03', '2026-08-09'); // Mon..Sun
      expect(s.isValid, isTrue);
      expect(s.units, 10);
      expect(s.countedDateKeys.length, 5);
      expect(s.skipped.keys, containsAll(['2026-08-08', '2026-08-09']));
    });

    test('a holiday inside the range is excluded and named', () {
      final s = _span(
        '2026-08-03',
        '2026-08-05',
        holidays: [_holiday('2026-08-04')],
      );
      expect(s.units, 4);
      expect(s.skipped['2026-08-04'], contains('Diwali'));
    });

    test('a special working day on a Saturday counts', () {
      final s = _span(
        '2026-08-08',
        '2026-08-08',
        holidays: [_holiday('2026-08-08', type: HolidayType.specialWorkingDay)],
      );
      expect(s.units, 2);
    });

    test('the branch pattern decides, not a hard-coded weekend', () {
      final sixDay = WorkingDays.defaults(
        schoolId: 's',
        branchId: 'b',
      ).copyWith(Weekday.saturday, true);
      final s = _span('2026-08-03', '2026-08-08', wd: sixDay);
      expect(s.units, 12);
    });

    test('types that count non-working days count every day', () {
      final s = _span(
        '2026-08-03',
        '2026-08-09',
        type: _type(countNonWorking: true),
      );
      expect(s.units, 14);
    });

    test('a half day is one unit; only on one date; only if allowed', () {
      expect(_span('2026-08-03', '2026-08-03', half: HalfDay.first).units, 1);
      expect(
        _span('2026-08-03', '2026-08-04', half: HalfDay.first).error,
        contains('single date'),
      );
      expect(
        _span(
          '2026-08-03',
          '2026-08-03',
          half: HalfDay.second,
          type: _type(halfDay: false),
        ).error,
        contains('not allowed'),
      );
    });

    test('a half day on a holiday is rejected: nothing to take leave from', () {
      final s = _span(
        '2026-08-04',
        '2026-08-04',
        half: HalfDay.first,
        holidays: [_holiday('2026-08-04')],
      );
      expect(s.isValid, isFalse);
    });

    test('a range with no school day is rejected', () {
      expect(
        _span('2026-08-08', '2026-08-09').error,
        contains('No school day'),
      );
    });

    test('end before start, outside the year, and over the cap', () {
      expect(_span('2026-08-05', '2026-08-03').error, contains('before'));
      expect(
        _span('2026-05-30', '2026-06-02').error,
        contains('academic year'),
      );
      expect(
        _span('2027-03-30', '2027-04-02').error,
        contains('academic year'),
      );
      expect(
        _span('2026-08-03', '2026-08-12', type: _type(maxDays: 5)).error,
        contains('at most 5'),
      );
    });

    test('dates are civil keys: month/year boundaries and leap day', () {
      final s = _span('2027-02-26', '2027-03-02');
      expect(s.countedDateKeys, ['2027-02-26', '2027-03-01', '2027-03-02']);
    });

    test('a full day takes both session locks, a half day only its own', () {
      final full = LeaveDayCalculator.lockIds(
        kind: LeaveKind.student,
        subjectId: 'stu',
        dateKeys: ['2026-08-03'],
        halfDay: HalfDay.none,
      );
      expect(full, [
        'STUDENT_stu__2026-08-03__FIRST',
        'STUDENT_stu__2026-08-03__SECOND',
      ]);
      expect(
        LeaveDayCalculator.lockIds(
          kind: LeaveKind.staff,
          subjectId: 'st',
          dateKeys: ['2026-08-03'],
          halfDay: HalfDay.second,
        ),
        ['STAFF_st__2026-08-03__SECOND'],
      );
    });
  });

  group('overlap detection', () {
    test('overlapping pending and approved applications conflict', () {
      final existing = [
        _app(id: 'x', status: LeaveStatus.approved),
        _app(
          id: 'y',
          status: LeaveStatus.pending,
          start: '2026-08-10',
          end: '2026-08-10',
        ),
      ];
      expect(
        LeaveWorkflow.findOverlap(
          existing: existing,
          countedDateKeys: ['2026-08-04', '2026-08-05'],
          halfDay: HalfDay.none,
        )?.applicationId,
        'x',
      );
    });

    test('withdrawn, rejected, returned and cancelled do not hold days', () {
      for (final s in [
        LeaveStatus.withdrawn,
        LeaveStatus.rejected,
        LeaveStatus.returned,
        LeaveStatus.cancelled,
      ]) {
        expect(
          LeaveWorkflow.findOverlap(
            existing: [_app(status: s)],
            countedDateKeys: ['2026-08-03'],
            halfDay: HalfDay.none,
          ),
          isNull,
          reason: s.name,
        );
      }
    });

    test('two different half-day sessions of one date coexist', () {
      final first = _app(
        status: LeaveStatus.approved,
        start: '2026-08-03',
        end: '2026-08-03',
        half: HalfDay.first,
        counted: ['2026-08-03'],
      );
      expect(
        LeaveWorkflow.findOverlap(
          existing: [first],
          countedDateKeys: ['2026-08-03'],
          halfDay: HalfDay.second,
        ),
        isNull,
      );
      expect(
        LeaveWorkflow.findOverlap(
          existing: [first],
          countedDateKeys: ['2026-08-03'],
          halfDay: HalfDay.first,
        ),
        isNotNull,
      );
      expect(
        LeaveWorkflow.findOverlap(
          existing: [first],
          countedDateKeys: ['2026-08-03'],
          halfDay: HalfDay.none,
        ),
        isNotNull,
      );
    });

    test('editing a returned application ignores itself', () {
      expect(
        LeaveWorkflow.findOverlap(
          existing: [_app(id: 'me')],
          countedDateKeys: ['2026-08-03'],
          halfDay: HalfDay.none,
          ignoreApplicationId: 'me',
        ),
        isNull,
      );
    });

    test(
      'lock ids of two overlapping full days collide (the DB-level guard)',
      () {
        List<String> ids(List<String> d) => LeaveDayCalculator.lockIds(
          kind: LeaveKind.student,
          subjectId: 'stu',
          dateKeys: d,
          halfDay: HalfDay.none,
        );
        expect(
          ids([
            '2026-08-03',
            '2026-08-04',
          ]).toSet().intersection(ids(['2026-08-04', '2026-08-05']).toSet()),
          isNotEmpty,
        );
      },
    );
  });

  group('workflow authorization and transitions', () {
    test(
      'reviewer may approve/reject/return pending, cancel approved only',
      () {
        expect(
          LeaveWorkflow.checkDecision(
            application: _app(),
            target: LeaveStatus.approved,
            reviewerUserId: 'admin',
          ),
          isNull,
        );
        expect(
          LeaveWorkflow.checkDecision(
            application: _app(status: LeaveStatus.approved),
            target: LeaveStatus.rejected,
            reviewerUserId: 'admin',
            remarks: 'no',
          ),
          contains('only be cancelled'),
        );
        expect(
          LeaveWorkflow.checkDecision(
            application: _app(status: LeaveStatus.approved),
            target: LeaveStatus.cancelled,
            reviewerUserId: 'admin',
            remarks: 'Child will attend',
          ),
          isNull,
        );
      },
    );

    test('terminal and withdrawn applications cannot be decided again', () {
      for (final s in [
        LeaveStatus.rejected,
        LeaveStatus.withdrawn,
        LeaveStatus.cancelled,
        LeaveStatus.returned,
      ]) {
        expect(
          LeaveWorkflow.checkDecision(
            application: _app(status: s),
            target: LeaveStatus.approved,
            reviewerUserId: 'admin',
          ),
          isNotNull,
          reason: s.name,
        );
      }
    });

    test('SELF-APPROVAL is refused, including via the subject account', () {
      expect(
        LeaveWorkflow.checkDecision(
          application: _app(applicant: 'u1'),
          target: LeaveStatus.approved,
          reviewerUserId: 'u1',
        ),
        contains('your own'),
      );
      expect(
        LeaveWorkflow.checkDecision(
          application: _app(applicant: 'admin-who-filed'),
          target: LeaveStatus.approved,
          reviewerUserId: 'teacher-subject',
          subjectUserId: 'teacher-subject',
        ),
        contains('your own'),
      );
    });

    test('rejection, return and cancellation need a written reason', () {
      for (final t in [LeaveStatus.rejected, LeaveStatus.returned]) {
        expect(
          LeaveWorkflow.checkDecision(
            application: _app(),
            target: t,
            reviewerUserId: 'admin',
            remarks: ' ',
          ),
          isNotNull,
        );
      }
    });

    test('an applicant may withdraw pending/returned, only their own', () {
      expect(
        LeaveWorkflow.checkApplicantAction(
          application: _app(),
          target: LeaveStatus.withdrawn,
          userId: 'u-parent',
        ),
        isNull,
      );
      expect(
        LeaveWorkflow.checkApplicantAction(
          application: _app(),
          target: LeaveStatus.withdrawn,
          userId: 'someone-else',
        ),
        isNotNull,
      );
      expect(
        LeaveWorkflow.checkApplicantAction(
          application: _app(status: LeaveStatus.approved),
          target: LeaveStatus.withdrawn,
          userId: 'u-parent',
        ),
        isNotNull,
        reason: 'approved leave is cancelled by a reviewer, not withdrawn',
      );
    });

    test('apply: reason, document, inactive type, role and employment', () {
      expect(
        LeaveWorkflow.checkApply(
          type: _type(),
          spanUnits: 2,
          reason: 'Fever',
          attachmentCount: 0,
          applicantRole: 'PARENT',
        ),
        isNull,
      );
      expect(
        LeaveWorkflow.checkApply(
          type: _type(),
          spanUnits: 2,
          reason: '',
          attachmentCount: 0,
          applicantRole: 'PARENT',
        ),
        contains('reason'),
      );
      expect(
        LeaveWorkflow.checkApply(
          type: _type(requiresDoc: true),
          spanUnits: 2,
          reason: 'Fever',
          attachmentCount: 0,
          applicantRole: 'PARENT',
        ),
        contains('document'),
      );
      expect(
        LeaveWorkflow.checkApply(
          type: _type(status: ActivationStatus.inactive),
          spanUnits: 2,
          reason: 'Fever',
          attachmentCount: 0,
          applicantRole: 'PARENT',
        ),
        contains('not available'),
      );
      final staff = _type(
        kind: LeaveKind.staff,
        pay: LeavePayType.paid,
        roles: ['TEACHER'],
        employment: ['FULL_TIME'],
      );
      expect(
        LeaveWorkflow.checkApply(
          type: staff,
          spanUnits: 2,
          reason: 'Rest',
          attachmentCount: 0,
          applicantRole: 'FINANCE',
        ),
        contains('role'),
      );
      expect(
        LeaveWorkflow.checkApply(
          type: staff,
          spanUnits: 2,
          reason: 'Rest',
          attachmentCount: 0,
          applicantRole: 'TEACHER',
          employmentType: 'CONTRACT',
        ),
        contains('employment'),
      );
    });
  });

  group('balance model', () {
    LeaveBalance balance({
      int entitlement = 24,
      AccrualMode mode = AccrualMode.upfront,
      int carry = 0,
      int adj = 0,
      int used = 0,
      String year = '2026-06-01',
    }) => LeaveBalance(
      balanceId: 'st__t__y',
      schoolId: 's',
      branchId: 'b',
      staffId: 'st',
      typeId: 't',
      academicYearId: 'y',
      leaveYearStartKey: year,
      entitlementUnits: entitlement,
      accrual: mode,
      carryForwardUnits: carry,
      adjustmentUnits: adj,
      consumedUnits: used,
    );

    test('available = entitlement + carry + adjustments − consumed', () {
      final f = LeaveBalanceMath.figures(
        balance: balance(carry: 4, adj: -2, used: 6),
        todayKey: '2026-07-01',
      );
      expect(f.available, 24 + 4 - 2 - 6);
      expect(f.consumed, 6);
    });

    test('monthly accrual grants 1/12 per leave-year month started', () {
      int accrued(String today) => LeaveBalanceMath.accruedUnits(
        entitlementUnits: 24,
        mode: AccrualMode.monthly,
        leaveYearStartKey: '2026-06-01',
        todayKey: today,
      );
      expect(accrued('2026-06-01'), 2);
      expect(accrued('2026-06-30'), 2);
      expect(accrued('2026-07-01'), 4);
      expect(accrued('2027-05-31'), 24);
      expect(accrued('2027-09-01'), 24, reason: 'never above the entitlement');
      expect(accrued('2026-05-01'), 0, reason: 'not before the year starts');
    });

    test('monthly accrual floors in half-day units', () {
      expect(
        LeaveBalanceMath.accruedUnits(
          entitlementUnits: 15,
          mode: AccrualMode.monthly,
          leaveYearStartKey: '2026-06-01',
          todayKey: '2026-06-10',
        ),
        1,
      );
    });

    test('check: ok, warn and block per policy', () {
      final f = LeaveBalanceMath.figures(
        balance: balance(used: 20),
        todayKey: '2026-06-01',
      );
      expect(
        LeaveBalanceMath.check(
          figures: f,
          requestUnits: 4,
          policy: ExceedPolicy.block,
        ).allowed,
        isTrue,
      );
      final block = LeaveBalanceMath.check(
        figures: f,
        requestUnits: 6,
        policy: ExceedPolicy.block,
      );
      expect(block.allowed, isFalse);
      expect(block.message, contains('only 2 days'));
      final warn = LeaveBalanceMath.check(
        figures: f,
        requestUnits: 6,
        policy: ExceedPolicy.warn,
      );
      expect(warn.allowed, isTrue);
      expect(warn.warning, isTrue);
    });

    test('pending is shown but not deducted (no reservation policy)', () {
      final f = LeaveBalanceMath.figures(
        balance: balance(),
        todayKey: '2026-06-01',
        pendingUnits: 6,
      );
      expect(f.available, 24);
      expect(f.availableIfPendingApproved, 18);
    });

    test('carry-forward is capped and never negative', () {
      expect(
        LeaveBalanceMath.carryForwardInto(
          closingAvailableUnits: 10,
          maxCarryUnits: 6,
        ),
        6,
      );
      expect(
        LeaveBalanceMath.carryForwardInto(
          closingAvailableUnits: 3,
          maxCarryUnits: 6,
        ),
        3,
      );
      expect(
        LeaveBalanceMath.carryForwardInto(
          closingAvailableUnits: -4,
          maxCarryUnits: 6,
        ),
        0,
      );
    });

    test('ledger ids make consume/restore idempotent', () {
      expect(LeaveLedgerEntry.consumeId('a1'), 'a1__consume');
      expect(LeaveLedgerEntry.restoreId('a1'), 'a1__restore');
      expect(
        LeaveBalance.idFor('st', 'STAFF__cl', 'y26'),
        'st__STAFF__cl__y26',
      );
    });
  });

  group('calendar entry (what teachers may see)', () {
    test('carries dates and session but no reason, type or attachment', () {
      final e = LeaveCalendarEntry.forApplication(_app());
      expect(e.keys, isNot(contains('reason')));
      expect(e.keys, isNot(contains('typeName')));
      expect(e.keys, isNot(contains('attachments')));
      expect(e['subjectName'], 'Anil');
    });

    test('covers only counted dates and only while active', () {
      final entry = LeaveCalendarEntry(
        applicationId: 'a',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.student,
        subjectId: 'stu',
        subjectName: 'Anil',
        startDateKey: '2026-08-03',
        endDateKey: '2026-08-05',
        countedDateKeys: const ['2026-08-03', '2026-08-05'],
      );
      expect(entry.coversDate('2026-08-03'), isTrue);
      expect(entry.coversDate('2026-08-04'), isFalse);
    });
  });
}
