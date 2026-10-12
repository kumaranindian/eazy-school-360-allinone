import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/attendance_calendar.dart';
import '../domain/attendance_day.dart';
import '../domain/attendance_save_planner.dart';
import '../domain/attendance_sheet.dart';
import '../domain/attendance_status.dart';
import '../domain/attendance_tally.dart';

/// The one save algorithm shared by student and staff registers, so the
/// concurrency and audit behaviour cannot drift apart between them.
///
/// Inside a single Firestore transaction it:
/// 1. reads the day document and every entry's record;
/// 2. lets [AttendanceSavePlanner] compare each stored revision with the one
///    the user loaded — any difference is a [ConflictFailure] and **nothing
///    is written** (no silent overwrite, safe against two users saving the
///    same register, against retries, and against double-clicks: a retry
///    after success sees the new revisions and conflicts instead of
///    duplicating);
/// 3. writes only the changed records (revision + 1), one immutable history
///    entry per change, and the day document with freshly computed counts.
///
/// A class of N students costs N + 1 reads and (changed records × 2 + 1)
/// writes. Firestore retries the transaction itself if a document changes
/// between the reads and the commit.
abstract final class AttendanceRegisterTransaction {
  static Future<void> run({
    required FirebaseFirestore firestore,
    required DocumentReference<Map<String, dynamic>> dayRef,
    required CollectionReference<Map<String, dynamic>> recordsCollection,
    required List<AttendanceEntry> entries,
    required String Function(AttendanceEntry entry) recordIdFor,
    required CurrentAttendance Function(Map<String, dynamic> data) currentFrom,
    required Map<String, dynamic> Function(PlannedWrite write, String? reason)
    createData,
    required Map<String, dynamic> Function(PlannedWrite write, String? reason)
    updateData,
    required Map<String, dynamic> Function(
      PlannedWrite write,
      String? reason,
      String actorId,
    )
    historyData,
    required AttendanceDay Function(
      int revision,
      AttendanceDayStatus status,
      AttendanceTally tally,
    )
    buildDay,
    required Map<String, dynamic> Function(AttendanceDay day, String actorId)
    createDay,
    required int expectedDayRevision,
    required bool finalize,
    required String? reason,
    required String actorId,
    String? sectionId,
  }) async {
    await firestore.runTransaction((transaction) async {
      final daySnapshot = await transaction.get(dayRef);
      final storedRevision = daySnapshot.exists
          ? ((daySnapshot.data()!['revision'] as num?)?.toInt() ?? 1)
          : 0;
      if (storedRevision != expectedDayRevision) throw const ConflictFailure();
      final wasFinalized =
          daySnapshot.exists &&
          daySnapshot.data()![FirestoreFields.status] ==
              AttendanceDayStatus.finalized.wireValue;

      final current = <String, CurrentAttendance?>{};
      for (final entry in entries) {
        final snapshot = await transaction.get(
          recordsCollection.doc(recordIdFor(entry)),
        );
        current[entry.subjectId] = snapshot.exists
            ? currentFrom(snapshot.data()!)
            : null;
      }

      final plan = AttendanceSavePlanner.plan(
        entries: entries,
        current: current,
        sectionId: sectionId,
      );
      if (plan.hasConflicts) {
        final names = plan.conflicts.take(3).join(', ');
        final more = plan.conflicts.length > 3
            ? ' and ${plan.conflicts.length - 3} more'
            : '';
        throw ConflictFailure(
          'Attendance for $names$more was changed by someone else (or is already recorded elsewhere). Reload to review the latest.',
        );
      }
      if (finalize && plan.resultingTally.notMarked > 0) {
        throw ValidationFailure(
          'Mark every entry before finalizing (${plan.resultingTally.notMarked} not marked).',
        );
      }

      for (final write in plan.writes) {
        final ref = recordsCollection.doc(recordIdFor(write.entry));
        if (write.isNew) {
          transaction.set(ref, createData(write, reason));
        } else {
          transaction.update(ref, updateData(write, reason));
        }
        transaction.set(
          ref
              .collection(FirestoreFields.attendanceHistoryCollection)
              .doc('${write.newRevision}'),
          historyData(write, reason, actorId),
        );
      }

      final status = (finalize || wasFinalized)
          ? AttendanceDayStatus.finalized
          : AttendanceDayStatus.draft;
      final day = buildDay(storedRevision + 1, status, plan.resultingTally);
      if (daySnapshot.exists) {
        transaction.update(dayRef, day.toFirestoreUpdate(updatedBy: actorId));
      } else {
        transaction.set(dayRef, createDay(day, actorId));
      }
    });
  }

  static CalendarDayKind dayKindFrom(String? name) =>
      CalendarDayKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => CalendarDayKind.workingDay,
      );
}
