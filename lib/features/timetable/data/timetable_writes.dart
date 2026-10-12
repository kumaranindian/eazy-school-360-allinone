import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../domain/substitution.dart';
import '../domain/timetable.dart';
import '../domain/timetable_enums.dart';
import '../domain/timetable_repositories.dart';

/// The documents the timetable and substitution workflows write, as pure
/// functions. The repositories apply them in their batches/transactions, and
/// `test/timetable/timetable_write_contract_test.dart` exports the same maps
/// to `firestore-tests/fixtures/timetable-write-plans.json`, which
/// `timetable-contract.test.mjs` replays against the Firestore emulator with
/// the real `firestore.rules` — so the shapes the Dart code writes are
/// verified against the rules (the leave module's contract test caught two
/// real bugs this way).
abstract final class TimetableWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  // --------------------------------------------------------------- counters
  static Map<String, dynamic> counter({
    required String schoolId,
    required String branchId,
    required int last,
    required bool exists,
    required String uid,
  }) => exists
      ? {'last': last, ...stamp(uid)}
      : {
          FirestoreFields.schoolId: schoolId,
          FirestoreFields.branchId: branchId,
          'last': last,
          ...stamp(uid),
        };

  /// The branch publication lock: bumped by every publish / withdraw.
  static Map<String, dynamic> publishLock({
    required String schoolId,
    required String branchId,
    required int sequence,
    required bool exists,
    required String uid,
  }) => exists
      ? {'publishSeq': sequence, ...stamp(uid)}
      : {
          FirestoreFields.schoolId: schoolId,
          FirestoreFields.branchId: branchId,
          'publishSeq': sequence,
          ...stamp(uid),
        };

  static Map<String, dynamic> dayLock({
    required String schoolId,
    required String branchId,
    required String dateKey,
    required int sequence,
    required bool exists,
    required String uid,
  }) => exists
      ? {'seq': sequence, ...stamp(uid)}
      : {
          FirestoreFields.schoolId: schoolId,
          FirestoreFields.branchId: branchId,
          'dateKey': dateKey,
          'seq': sequence,
          ...stamp(uid),
        };

  // -------------------------------------------------------------- timetable
  static Map<String, dynamic> draftEditUpdate({
    required Timetable timetable,
    required int revision,
    required String uid,
  }) => {
    ...timetable.body(),
    'revision': revision,
    'lastEvent': TimetableEvent.edited.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> publishUpdate({
    required int revision,
    required int lockSequence,
    required String uid,
  }) => {
    FirestoreFields.status: TimetableStatus.published.wireValue,
    'revision': revision,
    'lastEvent': TimetableEvent.published.wireValue,
    'publishedBy': uid,
    'publishedAt': FieldValue.serverTimestamp(),
    'lockSeq': lockSequence,
    ...stamp(uid),
  };

  /// A published version fully replaced by [supersededBy].
  static Map<String, dynamic> supersedeUpdate({
    required int revision,
    required String supersededBy,
    required int lockSequence,
    required String uid,
  }) => {
    FirestoreFields.status: TimetableStatus.archived.wireValue,
    'revision': revision,
    'lastEvent': TimetableEvent.superseded.wireValue,
    'supersededBy': supersededBy,
    'lockSeq': lockSequence,
    ...stamp(uid),
  };

  /// A published version that started earlier: ends the day before.
  static Map<String, dynamic> truncateUpdate({
    required int revision,
    required String newEndKey,
    required String supersededBy,
    required int lockSequence,
    required String uid,
  }) => {
    'effectiveToKey': newEndKey,
    'revision': revision,
    'lastEvent': TimetableEvent.truncated.wireValue,
    'supersededBy': supersededBy,
    'lockSeq': lockSequence,
    ...stamp(uid),
  };

  static Map<String, dynamic> archiveUpdate({
    required int revision,
    required int? lockSequence,
    required String uid,
  }) => {
    FirestoreFields.status: TimetableStatus.archived.wireValue,
    'revision': revision,
    'lastEvent': TimetableEvent.archived.wireValue,
    if (lockSequence != null) 'lockSeq': lockSequence,
    ...stamp(uid),
  };

  static Map<String, dynamic> entryLive(bool live) => {'live': live};

  static Map<String, dynamic> history({
    required Timetable timetable,
    required int revision,
    required TimetableStatus toStatus,
    required TimetableEvent event,
    required TimetableActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: timetable.schoolId,
    FirestoreFields.branchId: timetable.branchId,
    'academicYearId': timetable.academicYearId,
    'timetableId': timetable.timetableId,
    'version': timetable.version,
    'title': timetable.title,
    'revision': revision,
    'toStatus': toStatus.wireValue,
    'event': event.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static String historyId(String timetableId, int revision) =>
      '${timetableId}__$revision';

  // ----------------------------------------------------------- notifications
  static Map<String, dynamic> notification({
    required String schoolId,
    required String branchId,
    required String recipientUserId,
    required String type,
    required String title,
    required String body,
    required String createdBy,
    String? timetableId,
    String? substitutionId,
    int? revision,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'audience': 'USER',
    'recipientUserId': recipientUserId,
    'type': type,
    'applicationId': null,
    'timetableId': timetableId,
    'substitutionId': substitutionId,
    'revision': revision,
    'title': title,
    'body': body,
    'createdBy': createdBy,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    'readAt': null,
  };

  static String publishedNoticeId(
    String timetableId,
    int revision,
    String uid,
  ) => '${timetableId}__PUBLISHED__${revision}__$uid';

  static String substitutionNoticeId(
    String substitutionId,
    int revision,
    String event,
    String uid,
  ) => '${substitutionId}__${event}__${revision}__$uid';

  // ------------------------------------------------------------ substitution
  static Map<String, dynamic> substitutionCreate(Substitution s, String uid) =>
      {
        ...s.body(),
        FirestoreFields.status: SubstitutionStatus.active.wireValue,
        'revision': s.revision,
        'lastEvent':
            (s.revision == 1
                    ? SubstitutionEvent.assigned
                    : SubstitutionEvent.reinstated)
                .wireValue,
        'cancelReason': null,
        FirestoreFields.createdAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.createdBy: uid,
        FirestoreFields.updatedBy: uid,
      };

  /// Reinstating a cancelled cover: same document, new substitute.
  static Map<String, dynamic> substitutionReinstate(
    Substitution s,
    int revision,
    String uid,
  ) => {
    'substituteTeacherId': s.substituteTeacherId,
    'substituteTeacherName': s.substituteTeacherName,
    'reasonKind': s.reasonKind.wireValue,
    'reason': s.reason.trim(),
    'leaveApplicationId': s.leaveApplicationId,
    FirestoreFields.status: SubstitutionStatus.active.wireValue,
    'revision': revision,
    'lastEvent': SubstitutionEvent.reinstated.wireValue,
    'cancelReason': null,
    ...stamp(uid),
  };

  static Map<String, dynamic> substitutionChange({
    required String substituteTeacherId,
    required String substituteTeacherName,
    required String reason,
    required int revision,
    required String uid,
  }) => {
    'substituteTeacherId': substituteTeacherId,
    'substituteTeacherName': substituteTeacherName,
    'reason': reason.trim(),
    'revision': revision,
    'lastEvent': SubstitutionEvent.changed.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> substitutionCancel({
    required String reason,
    required int revision,
    required String uid,
  }) => {
    FirestoreFields.status: SubstitutionStatus.cancelled.wireValue,
    'cancelReason': reason.trim(),
    'revision': revision,
    'lastEvent': SubstitutionEvent.cancelled.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> substitutionHistory({
    required Substitution s,
    required int revision,
    required SubstitutionEvent event,
    required String substituteTeacherName,
    required TimetableActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: s.schoolId,
    FirestoreFields.branchId: s.branchId,
    'substitutionId': s.substitutionId,
    'dateKey': s.dateKey,
    'revision': revision,
    'event': event.wireValue,
    'substituteTeacherId': s.substituteTeacherId,
    'substituteTeacherName': substituteTeacherName,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static String substitutionHistoryId(String id, int revision) =>
      '${id}__$revision';
}
