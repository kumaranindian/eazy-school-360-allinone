import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/leave_application.dart';
import '../domain/leave_enums.dart';
import '../domain/leave_repositories.dart';
import '../domain/leave_type.dart';
import 'leave_firestore.dart';

class FirebaseLeaveTypeRepository implements LeaveTypeRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveTypeRepository(this._firestore);

  @override
  Stream<List<LeaveType>> watchTypes(
    String schoolId,
    String branchId, {
    LeaveKind? kind,
  }) {
    Query<Map<String, dynamic>> q = LeavePaths(
      _firestore,
      schoolId,
      branchId,
    ).types;
    if (kind != null) q = q.where('kind', isEqualTo: kind.wireValue);
    // Leave types are a short configuration list; the bound is a guard.
    return q.limit(200).snapshots().map((s) {
      final list = [
        for (final d in s.docs) LeaveType.fromFirestore(d.data(), d.id),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  @override
  Future<void> saveType(
    LeaveType type, {
    required bool isNew,
    required String actorId,
  }) async {
    final problem = type.validate();
    if (problem != null) throw ValidationFailure(problem);
    final ref = LeavePaths(
      _firestore,
      type.schoolId,
      type.branchId,
    ).types.doc(type.typeId);
    try {
      if (isNew) {
        // A create never silently replaces: refuse a duplicate code.
        await _firestore.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) {
            throw const ValidationFailure(
              'A leave type with this code already exists.',
            );
          }
          tx.set(ref, type.toFirestoreCreate(actorId: actorId));
        });
      } else {
        await ref.update(type.toFirestoreUpdate(actorId: actorId));
      }
    } catch (error, stackTrace) {
      if (error is AppFailure) rethrow;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<bool> watchAllowAdminOnBehalf(String schoolId, String branchId) {
    return LeavePaths(_firestore, schoolId, branchId)
        .collection(FirestoreFields.leaveSettingsCollection)
        .doc('policy')
        .snapshots()
        .map((s) => s.exists && s.data()?['allowAdminOnBehalf'] == true);
  }

  @override
  Future<void> setAllowAdminOnBehalf(
    String schoolId,
    String branchId,
    bool allow, {
    required String actorId,
  }) async {
    try {
      await LeavePaths(
        _firestore,
        schoolId,
        branchId,
      ).collection(FirestoreFields.leaveSettingsCollection).doc('policy').set({
        FirestoreFields.schoolId: schoolId,
        FirestoreFields.branchId: branchId,
        'allowAdminOnBehalf': allow,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: actorId,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseLeaveCalendarRepository implements LeaveCalendarRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveCalendarRepository(this._firestore);

  @override
  Future<List<LeaveCalendarEntry>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
    String? classId,
    String? sectionId,
    String? subjectId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = LeavePaths(
        _firestore,
        schoolId,
        branchId,
      ).calendar.where('subjectKind', isEqualTo: kind.wireValue);
      if (subjectId != null) {
        q = q.where('subjectId', isEqualTo: subjectId);
      } else {
        // Both pins when both are known: a teacher is allowed a section's
        // entries only when the query names the class AND the section.
        if (classId != null) q = q.where('classId', isEqualTo: classId);
        if (sectionId != null) q = q.where('sectionId', isEqualTo: sectionId);
      }
      final snapshot = await q
          .where('endDateKey', isGreaterThanOrEqualTo: fromKey)
          .orderBy('endDateKey')
          .limit(300)
          .get();
      return [
        for (final d in snapshot.docs)
          LeaveCalendarEntry.fromFirestore(d.data(), d.id),
      ].where((e) => e.active && e.startDateKey.compareTo(toKey) <= 0).toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseLeaveNotificationRepository
    implements LeaveNotificationRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveNotificationRepository(this._firestore);

  LeaveNotification _map(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    return LeaveNotification(
      notificationId: d.id,
      type: data['type'] as String? ?? '',
      applicationId: data['applicationId'] as String?,
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      read: data['readAt'] != null,
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
    );
  }

  @override
  Stream<List<LeaveNotification>> watchForUser(
    String schoolId,
    String branchId,
    String userId,
  ) {
    return LeavePaths(_firestore, schoolId, branchId).notifications
        .where('audience', isEqualTo: 'USER')
        .where('recipientUserId', isEqualTo: userId)
        .orderBy(FirestoreFields.createdAt, descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(_map).toList());
  }

  @override
  Stream<List<LeaveNotification>> watchForReviewers(
    String schoolId,
    String branchId,
  ) {
    return LeavePaths(_firestore, schoolId, branchId).notifications
        .where('audience', isEqualTo: 'REVIEWERS')
        .orderBy(FirestoreFields.createdAt, descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(_map).toList());
  }

  @override
  Future<void> markRead(
    String schoolId,
    String branchId,
    String notificationId,
  ) async {
    try {
      await LeavePaths(_firestore, schoolId, branchId).notifications
          .doc(notificationId)
          .update({'readAt': FieldValue.serverTimestamp()});
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

/// Report figures from aggregate queries — `count()` and `sum('units')` run
/// on the server and download no documents. Only APPROVED leave contributes
/// units; the range is on the application's start date.
class FirebaseLeaveReportRepository implements LeaveReportRepository {
  final FirebaseFirestore _firestore;

  FirebaseLeaveReportRepository(this._firestore);

  Query<Map<String, dynamic>> _base(
    String schoolId,
    String branchId,
    LeaveKind kind,
    String fromKey,
    String toKey,
  ) => LeavePaths(_firestore, schoolId, branchId).applications
      .where('subjectKind', isEqualTo: kind.wireValue)
      .where('startDateKey', isGreaterThanOrEqualTo: fromKey)
      .where('startDateKey', isLessThanOrEqualTo: toKey);

  Future<(int, int)> _countAndUnits(Query<Map<String, dynamic>> q) async {
    final agg = await q.aggregate(count(), sum('units')).get();
    return (agg.count ?? 0, (agg.getSum('units') ?? 0).toInt());
  }

  @override
  Future<LeaveStatusCounts> statusCounts({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final result = <LeaveStatus, int>{};
      for (final status in LeaveStatus.values) {
        final agg = await _base(schoolId, branchId, kind, fromKey, toKey)
            .where(FirestoreFields.status, isEqualTo: status.wireValue)
            .count()
            .get();
        result[status] = agg.count ?? 0;
      }
      return LeaveStatusCounts(result);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<LeaveTypeUsage> typeUsage({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String typeId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final (n, units) = await _countAndUnits(
        _base(schoolId, branchId, kind, fromKey, toKey)
            .where(FirestoreFields.status, isEqualTo: 'APPROVED')
            .where('typeId', isEqualTo: typeId),
      );
      return LeaveTypeUsage(typeId: typeId, applications: n, units: units);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<LeaveSectionSummary> sectionSummary({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final (n, units) = await _countAndUnits(
        _base(schoolId, branchId, LeaveKind.student, fromKey, toKey)
            .where(FirestoreFields.status, isEqualTo: 'APPROVED')
            .where('classId', isEqualTo: classId)
            .where('sectionId', isEqualTo: sectionId),
      );
      return LeaveSectionSummary(
        classId: classId,
        sectionId: sectionId,
        applications: n,
        units: units,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> subjectUnits({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final (_, units) = await _countAndUnits(
        _base(schoolId, branchId, kind, fromKey, toKey)
            .where(FirestoreFields.status, isEqualTo: 'APPROVED')
            .where('subjectId', isEqualTo: subjectId),
      );
      return units;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
