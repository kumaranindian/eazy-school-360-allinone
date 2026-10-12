import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/leave_balance.dart';
import '../domain/leave_enums.dart';
import '../domain/leave_repositories.dart';
import 'leave_firestore.dart';
import 'leave_writes.dart';

/// Balances and the ledger. A balance moves only together with an append-only
/// ledger entry (the rules require it), and consume/restore entries have ids
/// derived from the application, so neither can be applied twice.
class FirebaseLeaveBalanceRepository implements LeaveBalanceRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveBalanceRepository(this._firestore);

  LeavePaths _paths(String schoolId, String branchId) =>
      LeavePaths(_firestore, schoolId, branchId);

  @override
  Future<LeaveBalance?> getBalance(
    String schoolId,
    String branchId,
    String balanceId,
  ) async {
    try {
      final s = await _paths(schoolId, branchId).balances.doc(balanceId).get();
      return s.exists ? LeaveBalance.fromFirestore(s.data()!, s.id) : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<LeaveBalance>> watchStaffBalances({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String academicYearId,
  }) {
    return _paths(schoolId, branchId).balances
        .where('staffId', isEqualTo: staffId)
        .where('academicYearId', isEqualTo: academicYearId)
        .snapshots()
        .map(
          (s) => [
            for (final d in s.docs) LeaveBalance.fromFirestore(d.data(), d.id),
          ],
        );
  }

  @override
  Future<PagedResult<LeaveLedgerEntry>> fetchLedger({
    required String schoolId,
    required String branchId,
    required String staffId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      var q = _paths(schoolId, branchId).ledger
          .where('staffId', isEqualTo: staffId)
          .orderBy('at', descending: true);
      final start = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (start != null) q = q.startAfterDocument(start);
      final snapshot = await q.limit(pageSize + 1).get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: [
          for (final d in docs) LeaveLedgerEntry.fromFirestore(d.data(), d.id),
        ],
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> adjust({
    required LeaveBalance balance,
    required bool balanceExists,
    required int units,
    required String reason,
    required LeaveActor actor,
    required String requestId,
    String? staffUserId,
  }) async {
    if (units == 0) {
      throw const ValidationFailure('Enter an adjustment other than zero.');
    }
    if (reason.trim().length < 3) {
      throw const ValidationFailure('Give a reason for the adjustment.');
    }
    final p = _paths(balance.schoolId, balance.branchId);
    final balanceRef = p.balances.doc(balance.balanceId);
    final ledgerRef = p.ledger.doc(requestId);
    try {
      if (!balanceExists) {
        await balanceRef.set(balance.toFirestoreCreate(actorId: actor.userId));
      }
      await _firestore.runTransaction((tx) async {
        // Idempotent retry of the same dialog submission.
        if ((await tx.get(ledgerRef)).exists) return;
        final snap = await tx.get(balanceRef);
        if (!snap.exists) {
          throw const NotFoundFailure('This balance could not be found.');
        }
        final current = LeaveBalance.fromFirestore(snap.data()!, snap.id);
        tx.set(
          ledgerRef,
          LeaveWrites.ledgerEntry(
            application: null,
            schoolId: balance.schoolId,
            branchId: balance.branchId,
            staffId: balance.staffId,
            typeId: balance.typeId,
            academicYearId: balance.academicYearId,
            balanceId: balance.balanceId,
            type: LedgerEntryType.adjustment,
            units: units,
            reason: reason,
            actor: actor,
          ),
        );
        tx.update(
          balanceRef,
          LeaveWrites.balanceAdjustedUpdate(
            adjustmentUnits: current.adjustmentUnits + units,
            ledgerId: requestId,
            uid: actor.userId,
          ),
        );
        if (staffUserId != null) {
          tx.set(
            p.notifications.doc('adj__$requestId'),
            LeaveWrites.adjustmentNotification(
              schoolId: balance.schoolId,
              branchId: balance.branchId,
              staffUserId: staffUserId,
              units: units,
              reason: reason,
              createdBy: actor.userId,
            ),
          );
        }
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> carryForward({
    required LeaveBalance toBalance,
    required int carryUnits,
    required LeaveActor actor,
  }) async {
    if (carryUnits <= 0) {
      throw const ValidationFailure('There is nothing to carry forward.');
    }
    final p = _paths(toBalance.schoolId, toBalance.branchId);
    final ledgerId = '${toBalance.balanceId}__carry';
    final batch = _firestore.batch();
    batch.set(
      p.ledger.doc(ledgerId),
      LeaveWrites.ledgerEntry(
        application: null,
        schoolId: toBalance.schoolId,
        branchId: toBalance.branchId,
        staffId: toBalance.staffId,
        typeId: toBalance.typeId,
        academicYearId: toBalance.academicYearId,
        balanceId: toBalance.balanceId,
        type: LedgerEntryType.carryForward,
        units: carryUnits,
        reason: 'Carried forward from the previous leave year',
        actor: actor,
      ),
    );
    batch.set(
      p.balances.doc(toBalance.balanceId),
      LeaveWrites.balanceCreatedByCarry(
        balance: toBalance,
        carryUnits: carryUnits,
        uid: actor.userId,
      ),
    );
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<LeaveBalance>> fetchTypeBalances({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String typeId,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).balances
          .where('academicYearId', isEqualTo: academicYearId)
          .where('typeId', isEqualTo: typeId)
          .limit(300)
          .get();
      return [
        for (final d in snapshot.docs)
          LeaveBalance.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
