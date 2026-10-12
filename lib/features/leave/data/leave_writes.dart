import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../domain/leave_application.dart';
import '../domain/leave_balance.dart';
import '../domain/leave_days.dart';
import '../domain/leave_enums.dart';
import '../domain/leave_repositories.dart';

/// The documents the leave workflow writes, as pure functions of their inputs.
///
/// The repositories apply these inside their batches/transactions, and
/// `test/leave/leave_write_contract_test.dart` exports the same maps to
/// `firestore-tests/fixtures/leave-write-plans.json`, which
/// `leave-contract.test.mjs` replays against the Firestore emulator with the
/// real `firestore.rules`. So the shapes the Dart code writes are verified
/// against the security rules, not merely assumed to match them.
abstract final class LeaveWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  static Map<String, dynamic> history(
    LeaveApplication a, {
    required int revision,
    required LeaveStatus? from,
    required LeaveStatus to,
    required LeaveEvent event,
    required LeaveActor actor,
    String? remarks,
  }) => {
    FirestoreFields.schoolId: a.schoolId,
    FirestoreFields.branchId: a.branchId,
    'applicationId': a.applicationId,
    'revision': revision,
    'fromStatus': from?.wireValue,
    'toStatus': to.wireValue,
    'event': event.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'remarks': (remarks ?? '').trim().isEmpty ? null : remarks!.trim(),
    'at': FieldValue.serverTimestamp(),
    'applicantUserId': a.applicantUserId,
    'subjectKind': a.kind.wireValue,
    'subjectId': a.subjectId,
  };

  static String historyId(String applicationId, int revision) =>
      '${applicationId}__$revision';

  /// `{applicationId}__{event}__{revision}__{recipient|REVIEWERS}`.
  static String notificationId(
    LeaveApplication a,
    LeaveEvent event,
    int revision,
    String? recipientUserId,
  ) =>
      '${a.applicationId}__${event.wireValue}__${revision}__${recipientUserId ?? 'REVIEWERS'}';

  static Map<String, dynamic> notification({
    required LeaveApplication application,
    required String type,
    required int revision,
    required String createdBy,
    required String title,
    required String body,
    String? recipientUserId,
  }) => {
    FirestoreFields.schoolId: application.schoolId,
    FirestoreFields.branchId: application.branchId,
    'audience': recipientUserId == null ? 'REVIEWERS' : 'USER',
    'recipientUserId': recipientUserId,
    'type': type,
    'applicationId': application.applicationId,
    'revision': revision,
    'title': title,
    'body': body,
    'createdBy': createdBy,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    'readAt': null,
  };

  /// (lockId, data) for every day-session the application holds.
  static List<(String, Map<String, dynamic>)> locks(
    LeaveApplication a,
    String uid,
  ) => [
    for (final id in LeaveDayCalculator.lockIds(
      kind: a.kind,
      subjectId: a.subjectId,
      dateKeys: a.countedDateKeys,
      halfDay: a.halfDay,
    ))
      (
        id,
        {
          FirestoreFields.schoolId: a.schoolId,
          FirestoreFields.branchId: a.branchId,
          'lockedBy': uid,
          'applicationId': a.applicationId,
          'subjectKind': a.kind.wireValue,
          'subjectId': a.subjectId,
          'dateKey': id.split('__')[1],
          'slot': id.split('__')[2],
        },
      ),
  ];

  static Map<String, dynamic> withdrawUpdate(int revision, String uid) => {
    FirestoreFields.status: LeaveStatus.withdrawn.wireValue,
    'revision': revision,
    'lastEvent': LeaveEvent.withdraw.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> resubmitUpdate(
    LeaveApplication a,
    int revision,
    String uid,
  ) => {
    ...a.body(),
    FirestoreFields.status: LeaveStatus.pending.wireValue,
    'revision': revision,
    'lastEvent': LeaveEvent.resubmit.wireValue,
    'decidedBy': null,
    'decidedByName': null,
    'decidedAt': null,
    'decisionRemarks': null,
    ...stamp(uid),
  };

  static LeaveEvent eventFor(LeaveStatus target) => switch (target) {
    LeaveStatus.approved => LeaveEvent.approve,
    LeaveStatus.rejected => LeaveEvent.reject,
    LeaveStatus.cancelled => LeaveEvent.cancel,
    _ => LeaveEvent.returnForCorrection,
  };

  static Map<String, dynamic> decisionUpdate({
    required LeaveStatus target,
    required int revision,
    required LeaveActor reviewer,
    String? remarks,
  }) => {
    FirestoreFields.status: target.wireValue,
    'revision': revision,
    'lastEvent': eventFor(target).wireValue,
    'decidedBy': reviewer.userId,
    'decidedByName': reviewer.name,
    'decidedAt': FieldValue.serverTimestamp(),
    'decisionRemarks': (remarks ?? '').trim().isEmpty ? null : remarks!.trim(),
    ...stamp(reviewer.userId),
  };

  static Map<String, dynamic> ledgerEntry({
    required LeaveApplication? application,
    required String schoolId,
    required String branchId,
    required String staffId,
    required String typeId,
    required String? academicYearId,
    required String balanceId,
    required LedgerEntryType type,
    required int units,
    String? reason,
    required LeaveActor actor,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'staffId': staffId,
    'typeId': typeId,
    'academicYearId': academicYearId,
    'balanceId': balanceId,
    'entryType': type.wireValue,
    'units': units,
    'applicationId': application?.applicationId,
    'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    'actorId': actor.userId,
    'actorName': actor.name,
    'at': FieldValue.serverTimestamp(),
  };

  /// A balance moved by exactly one ledger entry.
  static Map<String, dynamic> balanceConsumedUpdate({
    required int consumedUnits,
    required String ledgerId,
    required String uid,
  }) => {
    'consumedUnits': consumedUnits,
    'lastLedgerId': ledgerId,
    ...stamp(uid),
  };

  static Map<String, dynamic> balanceAdjustedUpdate({
    required int adjustmentUnits,
    required String ledgerId,
    required String uid,
  }) => {
    'adjustmentUnits': adjustmentUnits,
    'lastLedgerId': ledgerId,
    ...stamp(uid),
  };

  /// A balance created by its first approval: already consumed.
  static Map<String, dynamic> balanceCreatedByConsume({
    required LeaveBalance balance,
    required int units,
    required String ledgerId,
    required String uid,
  }) => {
    ...balance.toFirestoreCreate(actorId: uid),
    'consumedUnits': units,
    'lastLedgerId': ledgerId,
  };

  static Map<String, dynamic> balanceCreatedByCarry({
    required LeaveBalance balance,
    required int carryUnits,
    required String uid,
  }) => {
    ...balance.toFirestoreCreate(actorId: uid),
    'carryForwardUnits': carryUnits,
  };

  static Map<String, dynamic> adjustmentNotification({
    required String schoolId,
    required String branchId,
    required String staffUserId,
    required int units,
    required String reason,
    required String createdBy,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'audience': 'USER',
    'recipientUserId': staffUserId,
    'type': 'LEAVE_BALANCE_ADJUSTED',
    'applicationId': null,
    'revision': null,
    'title': 'Your leave balance was adjusted',
    'body': '${units > 0 ? '+' : ''}${units / 2} day(s): ${reason.trim()}',
    'createdBy': createdBy,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    'readAt': null,
  };
}
