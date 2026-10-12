import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/leave_application.dart';
import '../domain/leave_balance.dart';
import '../domain/leave_days.dart';
import '../domain/leave_enums.dart';
import '../domain/leave_repositories.dart';
import '../domain/leave_type.dart';
import '../domain/leave_workflow.dart';
import 'leave_firestore.dart';
import 'leave_writes.dart';

/// Applications and their workflow.
///
/// **What makes a decision safe.** [decide] and [cancelApproved] are
/// Firestore transactions: they re-read the application, refuse it unless it
/// is still in the state the decision applies to, and write the new status,
/// the append-only history record, the calendar entry, the ledger entry and
/// the balance together. Two reviewers racing are serialised; the loser sees
/// a non-PENDING application and is refused — and `firestore.rules` re-checks
/// the same preconditions at commit, so a hand-built request cannot decide a
/// finished application, decide its own, or move a balance without its
/// ledger entry. What neither can stop is a reviewer who legitimately holds
/// the permission approving something they should not: every decision names
/// its reviewer in the history.
class FirebaseLeaveApplicationRepository implements LeaveApplicationRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveApplicationRepository(this._firestore);

  LeavePaths _paths(String schoolId, String branchId) =>
      LeavePaths(_firestore, schoolId, branchId);

  void _writeLocks(
    WriteBatch batch,
    LeavePaths p,
    LeaveApplication a,
    String uid,
  ) {
    for (final (id, data) in LeaveWrites.locks(a, uid)) {
      batch.set(p.locks.doc(id), data);
    }
  }

  List<DocumentReference<Map<String, dynamic>>> _lockRefs(
    LeavePaths p,
    LeaveApplication a,
  ) => [
    for (final id in LeaveDayCalculator.lockIds(
      kind: a.kind,
      subjectId: a.subjectId,
      dateKeys: a.countedDateKeys,
      halfDay: a.halfDay,
    ))
      p.locks.doc(id),
  ];

  @override
  Future<void> submit(LeaveApplication a, {required LeaveActor actor}) async {
    final p = _paths(a.schoolId, a.branchId);
    final batch = _firestore.batch();
    batch.set(p.applications.doc(a.applicationId), a.toFirestoreCreate());
    batch.set(
      p.history.doc('${a.applicationId}__1'),
      LeaveWrites.history(
        a,
        revision: 1,
        from: null,
        to: LeaveStatus.pending,
        event: LeaveEvent.submit,
        actor: actor,
      ),
    );
    _writeLocks(batch, p, a, actor.userId);
    batch.set(
      p.notifications.doc(
        LeaveWrites.notificationId(a, LeaveEvent.submit, 1, null),
      ),
      LeaveWrites.notification(
        application: a,
        type: 'LEAVE_SUBMITTED',
        revision: 1,
        createdBy: actor.userId,
        title: 'New ${a.kind.displayName.toLowerCase()} leave request',
        body: LeavePaths.describe(a),
      ),
    );
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      // A retry of a commit that actually succeeded is not an error.
      if (await _alreadyFiled(p, a)) return;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<bool> _alreadyFiled(LeavePaths p, LeaveApplication a) async {
    try {
      final existing = await p.applications.doc(a.applicationId).get();
      return existing.exists &&
          existing.data()?['applicantUserId'] == a.applicantUserId;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> resubmit(LeaveApplication a, {required LeaveActor actor}) async {
    final p = _paths(a.schoolId, a.branchId);
    final ref = p.applications.doc(a.applicationId);
    try {
      final current = await ref.get();
      if (!current.exists) {
        throw const NotFoundFailure('This application could not be found.');
      }
      final fresh = LeaveApplication.fromFirestore(
        current.data()!,
        a.applicationId,
      );
      final error = LeaveWorkflow.checkApplicantAction(
        application: fresh,
        target: LeaveStatus.pending,
        userId: actor.userId,
      );
      if (error != null) throw ValidationFailure(error);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(ref, LeaveWrites.resubmitUpdate(a, rev, actor.userId));
      batch.set(
        p.history.doc('${a.applicationId}__$rev'),
        LeaveWrites.history(
          a,
          revision: rev,
          from: LeaveStatus.returned,
          to: LeaveStatus.pending,
          event: LeaveEvent.resubmit,
          actor: actor,
        ),
      );
      _writeLocks(batch, p, a, actor.userId);
      batch.set(
        p.notifications.doc(
          LeaveWrites.notificationId(a, LeaveEvent.resubmit, rev, null),
        ),
        LeaveWrites.notification(
          application: a,
          type: 'LEAVE_SUBMITTED',
          revision: rev,
          createdBy: actor.userId,
          title: 'Leave request resubmitted',
          body: LeavePaths.describe(a),
        ),
      );
      await batch.commit();
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> withdraw(LeaveApplication a, {required LeaveActor actor}) async {
    final error = LeaveWorkflow.checkApplicantAction(
      application: a,
      target: LeaveStatus.withdrawn,
      userId: actor.userId,
    );
    if (error != null) throw ValidationFailure(error);
    final p = _paths(a.schoolId, a.branchId);
    final rev = a.revision + 1;
    final batch = _firestore.batch();
    // `revision` is the optimistic-concurrency guard: if a reviewer decided
    // meanwhile, this commit is refused instead of overwriting the decision.
    batch.update(
      p.applications.doc(a.applicationId),
      LeaveWrites.withdrawUpdate(rev, actor.userId),
    );
    batch.set(
      p.history.doc('${a.applicationId}__$rev'),
      LeaveWrites.history(
        a,
        revision: rev,
        from: a.status,
        to: LeaveStatus.withdrawn,
        event: LeaveEvent.withdraw,
        actor: actor,
      ),
    );
    if (a.status.holdsDays) {
      for (final ref in _lockRefs(p, a)) {
        batch.delete(ref);
      }
    }
    batch.set(
      p.notifications.doc(
        LeaveWrites.notificationId(a, LeaveEvent.withdraw, rev, null),
      ),
      LeaveWrites.notification(
        application: a,
        type: 'LEAVE_WITHDRAWN',
        revision: rev,
        createdBy: actor.userId,
        title: 'Leave request withdrawn',
        body: LeavePaths.describe(a),
      ),
    );
    try {
      await batch.commit();
    } catch (e, st) {
      throw _staleOr(e, st);
    }
  }

  Object _staleOr(Object error, StackTrace st) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const ConflictFailure(
        'This application was just changed by someone else. '
        'Reload to see its latest state.',
      );
    }
    return mapExceptionToFailure(error, st);
  }

  @override
  Future<void> decide({
    required LeaveApplication application,
    required LeaveStatus target,
    required LeaveActor reviewer,
    String? remarks,
    String? subjectUserId,
    required String todayKey,
  }) async {
    final p = _paths(application.schoolId, application.branchId);
    final appRef = p.applications.doc(application.applicationId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(appRef);
        if (!snap.exists) {
          throw const NotFoundFailure('This application could not be found.');
        }
        final fresh = LeaveApplication.fromFirestore(
          snap.data()!,
          application.applicationId,
        );
        // A repeated click of the same decision by the same reviewer.
        if (fresh.status == target && fresh.decidedBy == reviewer.userId) {
          return;
        }
        if (fresh.status != LeaveStatus.pending &&
            fresh.revision != application.revision) {
          throw const ConflictFailure(
            'Someone else already decided this application. '
            'Reload to see the outcome.',
          );
        }
        final error = LeaveWorkflow.checkDecision(
          application: fresh,
          target: target,
          reviewerUserId: reviewer.userId,
          subjectUserId: subjectUserId,
          remarks: remarks,
        );
        if (error != null) throw ValidationFailure(error);

        final consumes =
            target == LeaveStatus.approved && fresh.balanceId != null;
        DocumentSnapshot<Map<String, dynamic>>? balanceSnap;
        DocumentSnapshot<Map<String, dynamic>>? typeSnap;
        if (consumes) {
          balanceSnap = await tx.get(p.balances.doc(fresh.balanceId!));
          if (!balanceSnap.exists) {
            typeSnap = await tx.get(p.types.doc(fresh.typeId));
          }
        }

        final rev = fresh.revision + 1;
        final event = LeaveWrites.eventFor(target);

        // ---- balance check + ledger + balance (tracked staff leave) -------
        if (consumes) {
          final ledgerId = LeaveLedgerEntry.consumeId(fresh.applicationId);
          final ledgerRef = p.ledger.doc(ledgerId);
          LeaveBalance balance;
          final exists = balanceSnap!.exists;
          if (exists) {
            balance = LeaveBalance.fromFirestore(
              balanceSnap.data()!,
              balanceSnap.id,
            );
          } else {
            if (typeSnap == null || !typeSnap.exists) {
              throw const NotFoundFailure(
                'The leave type of this application no longer exists.',
              );
            }
            final type = LeaveType.fromFirestore(typeSnap.data()!, typeSnap.id);
            balance = LeaveBalance.fromPolicy(
              schoolId: fresh.schoolId,
              branchId: fresh.branchId,
              staffId: fresh.subjectId,
              type: type,
              academicYearId: fresh.academicYearId!,
              leaveYearStartKey: fresh.leaveYearStartKey ?? todayKey,
            );
          }
          final figures = LeaveBalanceMath.figures(
            balance: balance,
            todayKey: todayKey,
          );
          final check = LeaveBalanceMath.check(
            figures: figures,
            requestUnits: fresh.units,
            policy: balance.exceedPolicy,
          );
          if (!check.allowed) throw ValidationFailure(check.message!);

          tx.set(
            ledgerRef,
            LeaveWrites.ledgerEntry(
              application: fresh,
              schoolId: fresh.schoolId,
              branchId: fresh.branchId,
              staffId: fresh.subjectId,
              typeId: fresh.typeId,
              academicYearId: fresh.academicYearId,
              balanceId: balance.balanceId,
              type: LedgerEntryType.consume,
              units: fresh.units,
              actor: reviewer,
            ),
          );
          if (exists) {
            tx.update(
              p.balances.doc(balance.balanceId),
              LeaveWrites.balanceConsumedUpdate(
                consumedUnits: balance.consumedUnits + fresh.units,
                ledgerId: ledgerId,
                uid: reviewer.userId,
              ),
            );
          } else {
            tx.set(
              p.balances.doc(balance.balanceId),
              LeaveWrites.balanceCreatedByConsume(
                balance: balance,
                units: fresh.units,
                ledgerId: ledgerId,
                uid: reviewer.userId,
              ),
            );
          }
        }

        // ---- the application, its history, the calendar, the locks --------
        tx.update(
          appRef,
          LeaveWrites.decisionUpdate(
            target: target,
            revision: rev,
            reviewer: reviewer,
            remarks: remarks,
          ),
        );
        tx.set(
          p.history.doc('${fresh.applicationId}__$rev'),
          LeaveWrites.history(
            fresh,
            revision: rev,
            from: fresh.status,
            to: target,
            event: event,
            actor: reviewer,
            remarks: remarks,
          ),
        );
        if (target == LeaveStatus.approved) {
          tx.set(
            p.calendar.doc(fresh.applicationId),
            LeaveCalendarEntry.forApplication(fresh),
          );
        } else {
          for (final ref in _lockRefs(p, fresh)) {
            tx.delete(ref);
          }
        }
        final type = switch (target) {
          LeaveStatus.approved => 'LEAVE_APPROVED',
          LeaveStatus.rejected => 'LEAVE_REJECTED',
          _ => 'LEAVE_RETURNED',
        };
        final title = switch (target) {
          LeaveStatus.approved => 'Leave approved',
          LeaveStatus.rejected => 'Leave rejected',
          _ => 'Leave returned for correction',
        };
        tx.set(
          p.notifications.doc(
            LeaveWrites.notificationId(
              fresh,
              event,
              rev,
              fresh.applicantUserId,
            ),
          ),
          LeaveWrites.notification(
            application: fresh,
            type: type,
            revision: rev,
            createdBy: reviewer.userId,
            title: title,
            body: LeavePaths.describe(fresh),
            recipientUserId: fresh.applicantUserId,
          ),
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _staleOr(error, stackTrace);
    }
  }

  @override
  Future<void> cancelApproved({
    required LeaveApplication application,
    required LeaveActor reviewer,
    required String remarks,
    String? subjectUserId,
  }) async {
    final p = _paths(application.schoolId, application.branchId);
    final appRef = p.applications.doc(application.applicationId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(appRef);
        if (!snap.exists) {
          throw const NotFoundFailure('This application could not be found.');
        }
        final fresh = LeaveApplication.fromFirestore(
          snap.data()!,
          application.applicationId,
        );
        if (fresh.status == LeaveStatus.cancelled &&
            fresh.decidedBy == reviewer.userId) {
          return;
        }
        final error = LeaveWorkflow.checkDecision(
          application: fresh,
          target: LeaveStatus.cancelled,
          reviewerUserId: reviewer.userId,
          subjectUserId: subjectUserId,
          remarks: remarks,
        );
        if (error != null) throw ValidationFailure(error);

        DocumentSnapshot<Map<String, dynamic>>? balanceSnap;
        if (fresh.balanceId != null) {
          balanceSnap = await tx.get(p.balances.doc(fresh.balanceId!));
        }
        final rev = fresh.revision + 1;

        if (fresh.balanceId != null) {
          if (balanceSnap == null || !balanceSnap.exists) {
            throw const NotFoundFailure(
              'The leave balance for this application could not be found.',
            );
          }
          final balance = LeaveBalance.fromFirestore(
            balanceSnap.data()!,
            balanceSnap.id,
          );
          if (balance.consumedUnits < fresh.units) {
            throw const ValidationFailure(
              'The balance has less consumed leave than this application '
              'would restore. Review the ledger before cancelling.',
            );
          }
          final ledgerId = LeaveLedgerEntry.restoreId(fresh.applicationId);
          tx.set(
            p.ledger.doc(ledgerId),
            LeaveWrites.ledgerEntry(
              application: fresh,
              schoolId: fresh.schoolId,
              branchId: fresh.branchId,
              staffId: fresh.subjectId,
              typeId: fresh.typeId,
              academicYearId: fresh.academicYearId,
              balanceId: balance.balanceId,
              type: LedgerEntryType.restore,
              units: fresh.units,
              reason: remarks,
              actor: reviewer,
            ),
          );
          tx.update(
            p.balances.doc(balance.balanceId),
            LeaveWrites.balanceConsumedUpdate(
              consumedUnits: balance.consumedUnits - fresh.units,
              ledgerId: ledgerId,
              uid: reviewer.userId,
            ),
          );
        }

        tx.update(
          appRef,
          LeaveWrites.decisionUpdate(
            target: LeaveStatus.cancelled,
            revision: rev,
            reviewer: reviewer,
            remarks: remarks,
          ),
        );
        tx.set(
          p.history.doc('${fresh.applicationId}__$rev'),
          LeaveWrites.history(
            fresh,
            revision: rev,
            from: LeaveStatus.approved,
            to: LeaveStatus.cancelled,
            event: LeaveEvent.cancel,
            actor: reviewer,
            remarks: remarks,
          ),
        );
        tx.update(p.calendar.doc(fresh.applicationId), {
          FirestoreFields.status: 'CANCELLED',
        });
        for (final ref in _lockRefs(p, fresh)) {
          tx.delete(ref);
        }
        tx.set(
          p.notifications.doc(
            LeaveWrites.notificationId(
              fresh,
              LeaveEvent.cancel,
              rev,
              fresh.applicantUserId,
            ),
          ),
          LeaveWrites.notification(
            application: fresh,
            type: 'LEAVE_CANCELLED',
            revision: rev,
            createdBy: reviewer.userId,
            title: 'Approved leave cancelled',
            body: LeavePaths.describe(fresh),
            recipientUserId: fresh.applicantUserId,
          ),
        );
      });
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw _staleOr(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<LeaveApplication>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      var q = _paths(
        schoolId,
        branchId,
      ).applications.where('subjectKind', isEqualTo: filter.kind.wireValue);
      if (filter.status != null) {
        q = q.where(
          FirestoreFields.status,
          isEqualTo: filter.status!.wireValue,
        );
      }
      if (filter.typeId != null) {
        q = q.where('typeId', isEqualTo: filter.typeId);
      }
      if (filter.sectionId != null) {
        q = q.where('sectionId', isEqualTo: filter.sectionId);
      } else if (filter.classId != null) {
        q = q.where('classId', isEqualTo: filter.classId);
      }
      if (filter.subjectId != null) {
        q = q.where('subjectId', isEqualTo: filter.subjectId);
      }
      if (filter.applicantUserId != null) {
        q = q.where('applicantUserId', isEqualTo: filter.applicantUserId);
      }
      var ordered = q.orderBy(FirestoreFields.createdAt, descending: true);
      final start = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (start != null) ordered = ordered.startAfterDocument(start);
      final snapshot = await ordered.limit(pageSize + 1).get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: [
          for (final d in docs) LeaveApplication.fromFirestore(d.data(), d.id),
        ],
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<LeaveApplication?> watch(
    String schoolId,
    String branchId,
    String applicationId,
  ) {
    return _paths(schoolId, branchId).applications
        .doc(applicationId)
        .snapshots()
        .map(
          (s) =>
              s.exists ? LeaveApplication.fromFirestore(s.data()!, s.id) : null,
        );
  }

  @override
  Future<List<LeaveApplication>> fetchForSubject({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).applications
          .where('subjectKind', isEqualTo: kind.wireValue)
          .where('subjectId', isEqualTo: subjectId)
          .orderBy(FirestoreFields.createdAt, descending: true)
          .limit(100)
          .get();
      return [
        for (final d in snapshot.docs)
          LeaveApplication.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<LeaveHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String applicationId, {
    required LeaveKind kind,
    required String subjectId,
  }) {
    return _paths(schoolId, branchId).history
        .where('subjectKind', isEqualTo: kind.wireValue)
        .where('subjectId', isEqualTo: subjectId)
        .where('applicationId', isEqualTo: applicationId)
        .orderBy('revision')
        .snapshots()
        .map(
          (s) => [
            for (final d in s.docs) LeaveHistoryEntry.fromFirestore(d.data()),
          ],
        );
  }

  @override
  Future<int> countPending({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
  }) async {
    try {
      final agg = await _paths(schoolId, branchId).applications
          .where('subjectKind', isEqualTo: kind.wireValue)
          .where(
            FirestoreFields.status,
            isEqualTo: LeaveStatus.pending.wireValue,
          )
          .count()
          .get();
      return agg.count ?? 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
