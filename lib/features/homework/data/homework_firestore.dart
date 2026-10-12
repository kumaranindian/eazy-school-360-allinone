import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';

/// Typed access to the homework and announcement collections of one branch.
class HomeworkCollections {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String branchId;

  HomeworkCollections(this.firestore, this.schoolId, this.branchId);

  DocumentReference<Map<String, dynamic>> get branch => firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      branch.collection(name);

  CollectionReference<Map<String, dynamic>> get homework =>
      collection(FirestoreFields.homeworkCollection);
  CollectionReference<Map<String, dynamic>> get homeworkHistory =>
      collection(FirestoreFields.homeworkHistoryCollection);
  CollectionReference<Map<String, dynamic>> get submissions =>
      collection(FirestoreFields.homeworkSubmissionsCollection);
  CollectionReference<Map<String, dynamic>> get revisions =>
      collection(FirestoreFields.homeworkRevisionsCollection);
  CollectionReference<Map<String, dynamic>> get announcements =>
      collection(FirestoreFields.announcementsCollection);
  CollectionReference<Map<String, dynamic>> get announcementHistory =>
      collection(FirestoreFields.announcementHistoryCollection);
  CollectionReference<Map<String, dynamic>> get notices =>
      collection(FirestoreFields.broadcastNoticesCollection);
  CollectionReference<Map<String, dynamic>> get notifications =>
      collection(FirestoreFields.notificationsCollection);
}
