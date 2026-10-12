import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../domain/leave_application.dart';

/// Typed access to the leave collections of one branch, plus the writers for
/// the records that always accompany a change (history, notification).
class LeavePaths {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String branchId;

  LeavePaths(this.firestore, this.schoolId, this.branchId);

  DocumentReference<Map<String, dynamic>> get branch => firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      branch.collection(name);

  CollectionReference<Map<String, dynamic>> get types =>
      collection(FirestoreFields.leaveTypesCollection);
  CollectionReference<Map<String, dynamic>> get applications =>
      collection(FirestoreFields.leaveApplicationsCollection);
  CollectionReference<Map<String, dynamic>> get history =>
      collection(FirestoreFields.leaveHistoryCollection);
  CollectionReference<Map<String, dynamic>> get calendar =>
      collection(FirestoreFields.leaveCalendarCollection);
  CollectionReference<Map<String, dynamic>> get locks =>
      collection(FirestoreFields.leaveDayLocksCollection);
  CollectionReference<Map<String, dynamic>> get balances =>
      collection(FirestoreFields.leaveBalancesCollection);
  CollectionReference<Map<String, dynamic>> get ledger =>
      collection(FirestoreFields.leaveLedgerCollection);
  CollectionReference<Map<String, dynamic>> get notifications =>
      collection(FirestoreFields.notificationsCollection);

  /// "Anil Kumar · 03/08/2026 to 04/08/2026".
  static String describe(LeaveApplication a) {
    String d(String k) {
      final p = k.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }

    return a.startDateKey == a.endDateKey
        ? '${a.subjectName} · ${d(a.startDateKey)}'
        : '${a.subjectName} · ${d(a.startDateKey)} to ${d(a.endDateKey)}';
  }
}
