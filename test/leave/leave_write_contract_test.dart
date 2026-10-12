import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/leave/data/leave_writes.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_balance.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_repositories.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents the Dart leave code writes, for each step of
/// each workflow, to `firestore-tests/fixtures/leave-write-plans.json`.
/// `firestore-tests/leave-contract.test.mjs` replays them against the
/// Firestore emulator under the real `firestore.rules`: every batch must be
/// accepted, so a renamed field or a changed value in Dart that the rules
/// would refuse fails there, not in production.
///
/// (A test that only wrote the file would prove nothing, so this one also
/// asserts the shape of what it exports.)
const _school = '__SCHOOL__';
const _branch = 'north';

Object? _encode(Object? v) {
  if (v is FieldValue) return {r'$serverTimestamp': true};
  if (v is Timestamp) {
    return {r'$time': v.toDate().toUtc().toIso8601String()};
  }
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _encode(e.value)};
  }
  if (v is List) return [for (final e in v) _encode(e)];
  return v;
}

class _Batch {
  final String as;
  final String label;
  final List<Map<String, Object?>> ops = [];

  _Batch(this.as, this.label);

  void set(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'set', 'path': path, 'data': _encode(data)});
  void update(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'update', 'path': path, 'data': _encode(data)});
  void delete(String path) => ops.add({'op': 'delete', 'path': path});

  Map<String, Object?> toJson() => {'as': as, 'label': label, 'ops': ops};
}

LeaveApplication _app({
  required String id,
  required LeaveKind kind,
  required String subjectId,
  required String applicant,
  required ApplicantRelation relation,
  required String typeId,
  required String typeName,
  required LeavePayType pay,
  String? balanceId,
  List<String> dates = const ['2026-08-03', '2026-08-04'],
  HalfDay half = HalfDay.none,
  int? units,
}) => LeaveApplication(
  applicationId: id,
  schoolId: _school,
  branchId: _branch,
  kind: kind,
  subjectId: subjectId,
  subjectName: kind == LeaveKind.student ? 'Anil Kumar' : 'Priya Iyer',
  subjectCode: 'CODE-1',
  academicYearId: 'y1',
  classId: kind == LeaveKind.student ? 'c5' : null,
  className: kind == LeaveKind.student ? 'Class 5' : null,
  sectionId: kind == LeaveKind.student ? 'sa' : null,
  sectionName: kind == LeaveKind.student ? 'A' : null,
  applicantUserId: applicant,
  applicantName: 'Applicant',
  relation: relation,
  typeId: typeId,
  typeName: typeName,
  payType: pay,
  startDateKey: dates.first,
  endDateKey: dates.last,
  halfDay: half,
  units: units ?? (half == HalfDay.none ? dates.length * 2 : 1),
  countedDateKeys: dates,
  reason: 'Fever and rest',
  balanceId: balanceId,
  leaveYearStartKey: '2026-06-01',
);

String _p(String collection, String id) => '$collection/$id';

_Batch _submit(String as, LeaveApplication a, {String label = 'submit'}) {
  final actor = LeaveActor(userId: as, name: 'Applicant');
  final b = _Batch(as, label);
  b.set(_p('leaveApplications', a.applicationId), a.toFirestoreCreate());
  b.set(
    _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 1)),
    LeaveWrites.history(
      a,
      revision: 1,
      from: null,
      to: LeaveStatus.pending,
      event: LeaveEvent.submit,
      actor: actor,
    ),
  );
  for (final (id, data) in LeaveWrites.locks(a, as)) {
    b.set(_p('leaveDayLocks', id), data);
  }
  b.set(
    _p(
      'notifications',
      LeaveWrites.notificationId(a, LeaveEvent.submit, 1, null),
    ),
    LeaveWrites.notification(
      application: a,
      type: 'LEAVE_SUBMITTED',
      revision: 1,
      createdBy: as,
      title: 'New leave request',
      body: 'x',
    ),
  );
  return b;
}

_Batch _approve(
  String as,
  LeaveApplication a, {
  LeaveBalance? balance,
  bool balanceExists = false,
  int consumedBefore = 0,
}) {
  final reviewer = LeaveActor(userId: as, name: 'Reviewer');
  final b = _Batch(as, 'approve');
  if (a.balanceId != null && balance != null) {
    final ledgerId = LeaveLedgerEntry.consumeId(a.applicationId);
    b.set(
      _p('leaveLedger', ledgerId),
      LeaveWrites.ledgerEntry(
        application: a,
        schoolId: _school,
        branchId: _branch,
        staffId: a.subjectId,
        typeId: a.typeId,
        academicYearId: a.academicYearId,
        balanceId: balance.balanceId,
        type: LedgerEntryType.consume,
        units: a.units,
        actor: reviewer,
      ),
    );
    if (balanceExists) {
      b.update(
        _p('leaveBalances', balance.balanceId),
        LeaveWrites.balanceConsumedUpdate(
          consumedUnits: consumedBefore + a.units,
          ledgerId: ledgerId,
          uid: as,
        ),
      );
    } else {
      b.set(
        _p('leaveBalances', balance.balanceId),
        LeaveWrites.balanceCreatedByConsume(
          balance: balance,
          units: a.units,
          ledgerId: ledgerId,
          uid: as,
        ),
      );
    }
  }
  b.update(
    _p('leaveApplications', a.applicationId),
    LeaveWrites.decisionUpdate(
      target: LeaveStatus.approved,
      revision: 2,
      reviewer: reviewer,
    ),
  );
  b.set(
    _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 2)),
    LeaveWrites.history(
      a,
      revision: 2,
      from: LeaveStatus.pending,
      to: LeaveStatus.approved,
      event: LeaveEvent.approve,
      actor: reviewer,
    ),
  );
  b.set(
    _p('leaveCalendar', a.applicationId),
    LeaveCalendarEntry.forApplication(a),
  );
  b.set(
    _p(
      'notifications',
      LeaveWrites.notificationId(a, LeaveEvent.approve, 2, a.applicantUserId),
    ),
    LeaveWrites.notification(
      application: a,
      type: 'LEAVE_APPROVED',
      revision: 2,
      createdBy: as,
      title: 'Leave approved',
      body: 'x',
      recipientUserId: a.applicantUserId,
    ),
  );
  return b;
}

void main() {
  test('exports the Dart write plans for the rules contract test', () {
    final type = LeaveType(
      typeId: 'STAFF__cl',
      schoolId: _school,
      branchId: _branch,
      kind: LeaveKind.staff,
      code: 'CL',
      name: 'Casual leave',
      payType: LeavePayType.paid,
      annualEntitlementUnits: 24,
    );
    final balance = LeaveBalance.fromPolicy(
      schoolId: _school,
      branchId: _branch,
      staffId: 'staff-t',
      type: type,
      academicYearId: 'y1',
      leaveYearStartKey: '2026-06-01',
    );
    final scenarios = <Map<String, Object?>>[];

    // --- student: submit -> approve -> cancel -------------------------------
    {
      final a = _app(
        id: 'ct-s1',
        kind: LeaveKind.student,
        subjectId: 'stu-1',
        applicant: 'lv-parent',
        relation: ApplicantRelation.parent,
        typeId: 'STUDENT__sick',
        typeName: 'Sick leave',
        pay: LeavePayType.notApplicable,
      );
      final reviewer = const LeaveActor(userId: 'lv-admin2', name: 'R');
      final cancel = _Batch('lv-admin2', 'cancel approved');
      cancel.update(
        _p('leaveApplications', a.applicationId),
        LeaveWrites.decisionUpdate(
          target: LeaveStatus.cancelled,
          revision: 3,
          reviewer: reviewer,
          remarks: 'Child will attend',
        ),
      );
      cancel.set(
        _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 3)),
        LeaveWrites.history(
          a,
          revision: 3,
          from: LeaveStatus.approved,
          to: LeaveStatus.cancelled,
          event: LeaveEvent.cancel,
          actor: reviewer,
          remarks: 'Child will attend',
        ),
      );
      cancel.update(_p('leaveCalendar', a.applicationId), {
        'status': 'CANCELLED',
      });
      for (final (id, _) in LeaveWrites.locks(a, 'lv-parent')) {
        cancel.delete(_p('leaveDayLocks', id));
      }
      cancel.set(
        _p(
          'notifications',
          LeaveWrites.notificationId(
            a,
            LeaveEvent.cancel,
            3,
            a.applicantUserId,
          ),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_CANCELLED',
          revision: 3,
          createdBy: 'lv-admin2',
          title: 'Approved leave cancelled',
          body: 'x',
          recipientUserId: a.applicantUserId,
        ),
      );
      scenarios.add({
        'name': 'student: submit, approve, cancel',
        'batches': [
          _submit('lv-parent', a).toJson(),
          _approve('lv-admin', a).toJson(),
          cancel.toJson(),
        ],
      });
    }

    // --- student: withdraw ---------------------------------------------------
    {
      final a = _app(
        id: 'ct-s2',
        kind: LeaveKind.student,
        subjectId: 'stu-1',
        applicant: 'lv-parent',
        relation: ApplicantRelation.parent,
        typeId: 'STUDENT__sick',
        typeName: 'Sick leave',
        pay: LeavePayType.notApplicable,
        dates: const ['2026-09-07'],
      );
      final actor = const LeaveActor(userId: 'lv-parent', name: 'P');
      final w = _Batch('lv-parent', 'withdraw');
      w.update(
        _p('leaveApplications', a.applicationId),
        LeaveWrites.withdrawUpdate(2, 'lv-parent'),
      );
      w.set(
        _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 2)),
        LeaveWrites.history(
          a,
          revision: 2,
          from: LeaveStatus.pending,
          to: LeaveStatus.withdrawn,
          event: LeaveEvent.withdraw,
          actor: actor,
        ),
      );
      for (final (id, _) in LeaveWrites.locks(a, 'lv-parent')) {
        w.delete(_p('leaveDayLocks', id));
      }
      w.set(
        _p(
          'notifications',
          LeaveWrites.notificationId(a, LeaveEvent.withdraw, 2, null),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_WITHDRAWN',
          revision: 2,
          createdBy: 'lv-parent',
          title: 'Leave request withdrawn',
          body: 'x',
        ),
      );
      scenarios.add({
        'name': 'student: submit then withdraw',
        'batches': [_submit('lv-parent', a).toJson(), w.toJson()],
      });
    }

    // --- student: reject, return, resubmit ----------------------------------
    {
      final a = _app(
        id: 'ct-s3',
        kind: LeaveKind.student,
        subjectId: 'stu-1',
        applicant: 'lv-parent',
        relation: ApplicantRelation.parent,
        typeId: 'STUDENT__sick',
        typeName: 'Sick leave',
        pay: LeavePayType.notApplicable,
        dates: const ['2026-10-05', '2026-10-06'],
      );
      final reviewer = const LeaveActor(userId: 'lv-admin', name: 'R');
      final ret = _Batch('lv-admin', 'return for correction');
      ret.update(
        _p('leaveApplications', a.applicationId),
        LeaveWrites.decisionUpdate(
          target: LeaveStatus.returned,
          revision: 2,
          reviewer: reviewer,
          remarks: 'Add the doctor note',
        ),
      );
      ret.set(
        _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 2)),
        LeaveWrites.history(
          a,
          revision: 2,
          from: LeaveStatus.pending,
          to: LeaveStatus.returned,
          event: LeaveEvent.returnForCorrection,
          actor: reviewer,
          remarks: 'Add the doctor note',
        ),
      );
      for (final (id, _) in LeaveWrites.locks(a, 'lv-parent')) {
        ret.delete(_p('leaveDayLocks', id));
      }
      ret.set(
        _p(
          'notifications',
          LeaveWrites.notificationId(
            a,
            LeaveEvent.returnForCorrection,
            2,
            a.applicantUserId,
          ),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_RETURNED',
          revision: 2,
          createdBy: 'lv-admin',
          title: 'Leave returned for correction',
          body: 'x',
          recipientUserId: a.applicantUserId,
        ),
      );
      final parent = const LeaveActor(userId: 'lv-parent', name: 'P');
      final re = _Batch('lv-parent', 'resubmit');
      re.update(
        _p('leaveApplications', a.applicationId),
        LeaveWrites.resubmitUpdate(a, 3, 'lv-parent'),
      );
      re.set(
        _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 3)),
        LeaveWrites.history(
          a,
          revision: 3,
          from: LeaveStatus.returned,
          to: LeaveStatus.pending,
          event: LeaveEvent.resubmit,
          actor: parent,
        ),
      );
      for (final (id, data) in LeaveWrites.locks(a, 'lv-parent')) {
        re.set(_p('leaveDayLocks', id), data);
      }
      re.set(
        _p(
          'notifications',
          LeaveWrites.notificationId(a, LeaveEvent.resubmit, 3, null),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_SUBMITTED',
          revision: 3,
          createdBy: 'lv-parent',
          title: 'Leave request resubmitted',
          body: 'x',
        ),
      );
      scenarios.add({
        'name': 'student: return for correction, then resubmit',
        'batches': [
          _submit('lv-parent', a).toJson(),
          ret.toJson(),
          re.toJson(),
        ],
      });
    }

    // --- staff, tracked balance: submit, approve (creates balance), cancel,
    //     then a manual adjustment -------------------------------------------
    {
      final a = _app(
        id: 'ct-t1',
        kind: LeaveKind.staff,
        subjectId: 'staff-t',
        applicant: 'lv-teacher',
        relation: ApplicantRelation.self,
        typeId: 'STAFF__cl',
        typeName: 'Casual leave',
        pay: LeavePayType.paid,
        balanceId: balance.balanceId,
        dates: const ['2026-08-17', '2026-08-18'],
      );
      final reviewer = const LeaveActor(userId: 'lv-admin2', name: 'R');
      final cancel = _Batch('lv-admin2', 'cancel approved (restore balance)');
      final restoreId = LeaveLedgerEntry.restoreId(a.applicationId);
      cancel.set(
        _p('leaveLedger', restoreId),
        LeaveWrites.ledgerEntry(
          application: a,
          schoolId: _school,
          branchId: _branch,
          staffId: a.subjectId,
          typeId: a.typeId,
          academicYearId: a.academicYearId,
          balanceId: balance.balanceId,
          type: LedgerEntryType.restore,
          units: a.units,
          reason: 'Cover found',
          actor: reviewer,
        ),
      );
      cancel.update(
        _p('leaveBalances', balance.balanceId),
        LeaveWrites.balanceConsumedUpdate(
          consumedUnits: 0,
          ledgerId: restoreId,
          uid: 'lv-admin2',
        ),
      );
      cancel.update(
        _p('leaveApplications', a.applicationId),
        LeaveWrites.decisionUpdate(
          target: LeaveStatus.cancelled,
          revision: 3,
          reviewer: reviewer,
          remarks: 'Cover found',
        ),
      );
      cancel.set(
        _p('leaveHistory', LeaveWrites.historyId(a.applicationId, 3)),
        LeaveWrites.history(
          a,
          revision: 3,
          from: LeaveStatus.approved,
          to: LeaveStatus.cancelled,
          event: LeaveEvent.cancel,
          actor: reviewer,
          remarks: 'Cover found',
        ),
      );
      cancel.update(_p('leaveCalendar', a.applicationId), {
        'status': 'CANCELLED',
      });
      for (final (id, _) in LeaveWrites.locks(a, 'lv-teacher')) {
        cancel.delete(_p('leaveDayLocks', id));
      }
      cancel.set(
        _p(
          'notifications',
          LeaveWrites.notificationId(
            a,
            LeaveEvent.cancel,
            3,
            a.applicantUserId,
          ),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_CANCELLED',
          revision: 3,
          createdBy: 'lv-admin2',
          title: 'Approved leave cancelled',
          body: 'x',
          recipientUserId: a.applicantUserId,
        ),
      );

      final adjust = _Batch('lv-admin', 'manual adjustment');
      const adjId = 'adj_contract_1';
      adjust.set(
        _p('leaveLedger', adjId),
        LeaveWrites.ledgerEntry(
          application: null,
          schoolId: _school,
          branchId: _branch,
          staffId: 'staff-t',
          typeId: 'STAFF__cl',
          academicYearId: 'y1',
          balanceId: balance.balanceId,
          type: LedgerEntryType.adjustment,
          units: 4,
          reason: 'Granted for exam duty',
          actor: const LeaveActor(userId: 'lv-admin', name: 'A'),
        ),
      );
      adjust.update(
        _p('leaveBalances', balance.balanceId),
        LeaveWrites.balanceAdjustedUpdate(
          adjustmentUnits: 4,
          ledgerId: adjId,
          uid: 'lv-admin',
        ),
      );
      adjust.set(
        _p('notifications', 'adj__$adjId'),
        LeaveWrites.adjustmentNotification(
          schoolId: _school,
          branchId: _branch,
          staffUserId: 'lv-teacher',
          units: 4,
          reason: 'Granted for exam duty',
          createdBy: 'lv-admin',
        ),
      );

      scenarios.add({
        'name': 'staff: submit, approve (balance created), cancel, adjust',
        'batches': [
          _submit('lv-teacher', a).toJson(),
          _approve('lv-admin', a, balance: balance).toJson(),
          cancel.toJson(),
          adjust.toJson(),
        ],
      });
    }

    // --- staff half day, second request against an existing balance ---------
    {
      final a = _app(
        id: 'ct-t2',
        kind: LeaveKind.staff,
        subjectId: 'staff-t',
        applicant: 'lv-teacher',
        relation: ApplicantRelation.self,
        typeId: 'STAFF__cl',
        typeName: 'Casual leave',
        pay: LeavePayType.paid,
        balanceId: balance.balanceId,
        dates: const ['2026-11-02'],
        half: HalfDay.first,
      );
      scenarios.add({
        'name': 'staff: half day against an existing balance',
        'needsBalance': true,
        'batches': [
          _submit('lv-teacher', a).toJson(),
          _approve(
            'lv-admin',
            a,
            balance: balance,
            balanceExists: true,
            consumedBefore: 0,
          ).toJson(),
        ],
      });
    }

    final file = File('firestore-tests/fixtures/leave-write-plans.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'scenarios': scenarios}),
    );

    // Shape assertions: the export is not vacuous.
    expect(scenarios, hasLength(5));
    final first = (scenarios.first['batches'] as List).first as Map;
    final ops = first['ops'] as List;
    final application = ops.first as Map;
    expect(application['path'], 'leaveApplications/ct-s1');
    final data = application['data'] as Map;
    expect(data['status'], 'PENDING');
    expect(data['revision'], 1);
    expect(data['units'], 4);
    expect(data['createdAt'], {r'$serverTimestamp': true});
    expect(
      data['startDate'],
      containsPair(r'$time', '2026-08-03T00:00:00.000Z'),
    );
    // 2 dates x 2 sessions of locks, history, notification, application
    expect(ops, hasLength(1 + 1 + 4 + 1));
  });
}
