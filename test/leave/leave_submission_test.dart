import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_balance.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_submission.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:flutter_test/flutter_test.dart';

LeaveType _sick({
  bool doc = false,
  int? max,
  ActivationStatus status = ActivationStatus.active,
}) => LeaveType(
  typeId: 'STUDENT__sick',
  schoolId: 's',
  branchId: 'b',
  kind: LeaveKind.student,
  code: 'SICK',
  name: 'Sick leave',
  payType: LeavePayType.notApplicable,
  requiresDocument: doc,
  maxDaysPerRequest: max,
  status: status,
);

LeaveType _cl({
  int entitlement = 24,
  ExceedPolicy exceed = ExceedPolicy.block,
  AccrualMode accrual = AccrualMode.upfront,
}) => LeaveType(
  typeId: 'STAFF__cl',
  schoolId: 's',
  branchId: 'b',
  kind: LeaveKind.staff,
  code: 'CL',
  name: 'Casual leave',
  payType: LeavePayType.paid,
  annualEntitlementUnits: entitlement,
  exceedPolicy: exceed,
  accrual: accrual,
);

final _wd = WorkingDays.defaults(schoolId: 's', branchId: 'b');

SubmissionPlan _plan({
  LeaveType? type,
  String start = '2026-08-03',
  String end = '2026-08-04',
  HalfDay half = HalfDay.none,
  String? reason = 'Fever',
  int attachments = 0,
  List<Holiday> holidays = const [],
  List<LeaveApplication> existing = const [],
  String role = 'PARENT',
  LeaveBalance? balance,
  int pending = 0,
  String today = '2026-08-01',
}) => LeaveSubmissionPlanner.plan(
  type: type ?? _sick(),
  startKey: start,
  endKey: end,
  halfDay: half,
  reason: reason,
  attachmentCount: attachments,
  workingDays: _wd,
  calendarEntries: holidays,
  yearStartKey: '2026-06-01',
  yearEndKey: '2027-03-31',
  existing: existing,
  applicantRole: role,
  balance: balance,
  pendingUnits: pending,
  todayKey: today,
);

LeaveBalance _balance({
  int entitlement = 24,
  int used = 0,
  int carry = 0,
  int adj = 0,
  ExceedPolicy exceed = ExceedPolicy.block,
  AccrualMode accrual = AccrualMode.upfront,
}) => LeaveBalance(
  balanceId: 'st__t__y',
  schoolId: 's',
  branchId: 'b',
  staffId: 'st',
  typeId: 'STAFF__cl',
  academicYearId: 'y',
  leaveYearStartKey: '2026-06-01',
  entitlementUnits: entitlement,
  consumedUnits: used,
  carryForwardUnits: carry,
  adjustmentUnits: adj,
  exceedPolicy: exceed,
  accrual: accrual,
);

LeaveApplication _existing(
  String start,
  String end,
  LeaveStatus status, {
  HalfDay half = HalfDay.none,
}) => LeaveApplication(
  applicationId: 'e-$start',
  schoolId: 's',
  branchId: 'b',
  kind: LeaveKind.student,
  subjectId: 'stu',
  subjectName: 'A',
  applicantUserId: 'u',
  applicantName: 'P',
  relation: ApplicantRelation.parent,
  typeId: 'STUDENT__sick',
  typeName: 'Sick leave',
  payType: LeavePayType.notApplicable,
  startDateKey: start,
  endDateKey: end,
  halfDay: half,
  units: 2,
  countedDateKeys: start == end ? [start] : [start, end],
  status: status,
);

void main() {
  group('LeaveSubmissionPlanner', () {
    test('a valid student application is priced before it is sent', () {
      final p = _plan();
      expect(p.canSubmit, isTrue);
      expect(p.units, 4);
      expect(p.span!.countedDateKeys, ['2026-08-03', '2026-08-04']);
    });

    test('a weekend inside the range is skipped, not charged', () {
      final p = _plan(start: '2026-08-07', end: '2026-08-10');
      expect(p.units, 4); // Fri + Mon
      expect(p.span!.skipped.keys, containsAll(['2026-08-08', '2026-08-09']));
    });

    test('a holiday is skipped', () {
      final h = Holiday(
        holidayId: 'h',
        schoolId: 's',
        branchId: 'b',
        academicYearId: 'y',
        date: DateTime.utc(2026, 8, 4),
        name: 'Founders Day',
        type: HolidayType.school,
        status: ActivationStatus.active,
      );
      final p = _plan(holidays: [h]);
      expect(p.units, 2);
      expect(p.span!.skipped['2026-08-04'], contains('Founders Day'));
    });

    test('blocks: no type, bad range, reason, document, inactive type', () {
      expect(
        LeaveSubmissionPlanner.plan(
          type: null,
          startKey: '2026-08-03',
          endKey: '2026-08-03',
          halfDay: HalfDay.none,
          reason: 'x',
          attachmentCount: 0,
          workingDays: _wd,
          calendarEntries: const [],
          yearStartKey: '2026-06-01',
          yearEndKey: '2027-03-31',
          existing: const [],
          applicantRole: 'PARENT',
          todayKey: '2026-08-01',
        ).canSubmit,
        isFalse,
      );
      expect(
        _plan(start: '2026-08-05', end: '2026-08-03').error,
        contains('before'),
      );
      expect(_plan(reason: '').error, contains('reason'));
      expect(_plan(type: _sick(doc: true)).error, contains('document'));
      expect(_plan(type: _sick(doc: true), attachments: 1).canSubmit, isTrue);
      expect(
        _plan(type: _sick(status: ActivationStatus.inactive)).error,
        contains('not available'),
      );
    });

    test('overlap with a pending or approved application is blocked', () {
      final p = _plan(
        existing: [_existing('2026-08-04', '2026-08-05', LeaveStatus.pending)],
      );
      expect(p.canSubmit, isFalse);
      expect(p.error, contains('overlaps'));
    });

    test('overlap with a withdrawn or rejected one is fine', () {
      final p = _plan(
        existing: [
          _existing('2026-08-03', '2026-08-04', LeaveStatus.withdrawn),
          _existing('2026-08-03', '2026-08-04', LeaveStatus.rejected),
        ],
      );
      expect(p.canSubmit, isTrue);
    });

    test('staff: within balance passes; over a BLOCK balance is refused', () {
      final ok = _plan(
        type: _cl(),
        role: 'TEACHER',
        balance: _balance(used: 10),
        reason: 'Family',
      );
      expect(ok.canSubmit, isTrue);
      expect(ok.figures!.available, 14);

      final over = _plan(
        type: _cl(),
        role: 'TEACHER',
        balance: _balance(used: 22),
        reason: 'Family',
      );
      expect(over.canSubmit, isFalse);
      expect(over.error, contains('only 1 day is available'));
    });

    test('staff: over a WARN balance may be submitted, with a warning', () {
      final p = _plan(
        type: _cl(exceed: ExceedPolicy.warn),
        role: 'TEACHER',
        balance: _balance(used: 22, exceed: ExceedPolicy.warn),
        reason: 'Family',
      );
      expect(p.canSubmit, isTrue);
      expect(p.warning, isNotNull);
    });

    test('staff: monthly accrual limits what is available today', () {
      // 24 units monthly: 2 per month; in the first month only 2 units
      final p = _plan(
        type: _cl(accrual: AccrualMode.monthly),
        role: 'TEACHER',
        balance: _balance(accrual: AccrualMode.monthly),
        reason: 'Family',
        today: '2026-06-10',
      );
      expect(p.figures!.available, 2);
      expect(p.canSubmit, isFalse); // needs 4
    });

    test('staff: pending requests are shown but not deducted', () {
      final p = _plan(
        type: _cl(),
        role: 'TEACHER',
        balance: _balance(used: 18),
        reason: 'Family',
        pending: 4,
      );
      expect(p.figures!.available, 6);
      expect(p.canSubmit, isTrue);
      expect(p.warning, contains('awaiting approval'));
    });

    test('unpaid and untracked types never consult a balance', () {
      final unpaid = LeaveType(
        typeId: 'STAFF__ul',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        code: 'UL',
        name: 'Unpaid',
        payType: LeavePayType.unpaid,
      );
      final p = _plan(type: unpaid, role: 'TEACHER', reason: 'Personal');
      expect(p.canSubmit, isTrue);
      expect(p.figures, isNull);
    });

    test('a role or employment type outside the type\'s scope is refused', () {
      final t = LeaveType(
        typeId: 'STAFF__m',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        code: 'M',
        name: 'Maternity',
        payType: LeavePayType.paid,
        applicableRoles: const ['TEACHER'],
      );
      expect(
        _plan(type: t, role: 'FINANCE', reason: 'x1y').error,
        contains('role'),
      );
      expect(_plan(type: t, role: 'TEACHER', reason: 'x1y').canSubmit, isTrue);
    });
  });

  group('attendance overlay', () {
    LeaveCalendarEntry entry(
      String id,
      String subject, {
      HalfDay half = HalfDay.none,
      bool active = true,
      List<String> dates = const ['2026-08-03'],
    }) => LeaveCalendarEntry(
      applicationId: id,
      schoolId: 's',
      branchId: 'b',
      kind: LeaveKind.student,
      subjectId: subject,
      subjectName: subject,
      startDateKey: dates.first,
      endDateKey: dates.last,
      halfDay: half,
      countedDateKeys: dates,
      active: active,
    );

    test('only entries that cover the date and are active apply', () {
      final map = LeaveAttendanceOverlay.forDate([
        entry('1', 'a'),
        entry('2', 'b', dates: ['2026-08-04']),
        entry('3', 'c', active: false),
      ], '2026-08-03');
      expect(map.keys, ['a']);
    });

    test('a full-day entry wins over a half-day one for the same person', () {
      final map = LeaveAttendanceOverlay.forDate([
        entry('1', 'a', half: HalfDay.first),
        entry('2', 'a'),
      ], '2026-08-03');
      expect(map['a']!.halfDay, HalfDay.none);
      expect(LeaveAttendanceOverlay.label(map['a']!), 'On approved leave');
    });

    test('labels name the session', () {
      expect(
        LeaveAttendanceOverlay.label(entry('1', 'a', half: HalfDay.second)),
        'On approved leave (second half)',
      );
    });

    test('repeating the same approval does not duplicate the annotation', () {
      final e = entry('1', 'a');
      final map = LeaveAttendanceOverlay.forDate([e, e, e], '2026-08-03');
      expect(map, hasLength(1));
    });
  });
}
