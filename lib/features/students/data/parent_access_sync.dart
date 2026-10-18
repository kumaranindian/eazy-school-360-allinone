import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/utils/bounded_parallel.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/parent_access_keys.dart';
import '../domain/student.dart';

/// Keeps `parentAccess/{parentId}` (see [ParentAccessKeys]) in step with the
/// links and placements it summarises.
///
/// Called by staff-side writes (link a parent, change a link, transfer or
/// change the status of a student) and by the "Refresh parent access" action.
/// The index is derived data: the student and link documents stay the source
/// of truth, and the index is always recomputed *from them*, never patched.
///
/// Failure mode is safe in one direction only: a missing or short list
/// withholds content (fail closed); a stale list that is too long keeps old
/// access until the next refresh — which is why every relevant write
/// refreshes, and why the admin action exists.
class ParentAccessSync {
  final FirebaseFirestore _firestore;

  ParentAccessSync(this._firestore);

  DocumentReference<Map<String, dynamic>> _doc(
    String schoolId,
    String branchId,
    String parentId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection('parentAccess')
      .doc(parentId);

  CollectionReference<Map<String, dynamic>> _students(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.studentsCollection);

  /// Recomputes one family's index document for [branchId].
  Future<ParentAccessKeys> refreshParent({
    required String schoolId,
    required String branchId,
    required String parentId,
    required String updatedBy,
  }) async {
    final links = await _firestore
        .collectionGroup(FirestoreFields.parentLinksCollection)
        .where('schoolId', isEqualTo: schoolId)
        .where('branchId', isEqualTo: branchId)
        .where('parentId', isEqualTo: parentId)
        .get();
    final children = <Student>[];
    for (final link in links.docs) {
      final d = link.data();
      if (d['canAccessPortal'] != true || d['status'] != 'ACTIVE') continue;
      final studentId = d['studentId'] as String;
      final snap = await _students(schoolId, branchId).doc(studentId).get();
      if (snap.exists) {
        children.add(
          Student.fromFirestore(schoolId, branchId, studentId, snap.data()!),
        );
      }
    }
    final keys = ParentAccessKeys.forChildren(children, branchId: branchId);
    await _doc(schoolId, branchId, parentId).set({
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'parentId': parentId,
      'classKeys': keys.classKeys,
      'sectionKeys': keys.sectionKeys,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    });
    return keys;
  }

  /// Refreshes every family linked to [studentId] (any link status: a link
  /// that was just switched off must be removed from its index too).
  Future<void> refreshForStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String updatedBy,
  }) async {
    final links = await _students(
      schoolId,
      branchId,
    ).doc(studentId).collection(FirestoreFields.parentLinksCollection).get();
    for (final link in links.docs) {
      await refreshParent(
        schoolId: schoolId,
        branchId: branchId,
        parentId: link.id,
        updatedBy: updatedBy,
      );
    }
  }

  /// Same, but never lets an index problem fail the business write that
  /// triggered it: the problem is logged and the admin action can repair it.
  Future<void> refreshForStudentBestEffort({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String updatedBy,
  }) async {
    try {
      await refreshForStudent(
        schoolId: schoolId,
        branchId: branchId,
        studentId: studentId,
        updatedBy: updatedBy,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Parent access index could not be refreshed for a student; use '
        '"Refresh parent access" to repair it.',
        tag: 'ParentAccessSync',
      );
      mapExceptionToFailure(error, stackTrace); // logs the detail
    }
  }

  /// Recomputes the index for every parent of the branch. Also the backfill
  /// for data created before the index existed. Returns the number refreshed.
  Future<int> refreshBranch({
    required String schoolId,
    required String branchId,
    required String updatedBy,
  }) async {
    var count = 0;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    final parents = _firestore
        .collection(FirestoreFields.schoolsCollection)
        .doc(schoolId)
        .collection(FirestoreFields.branchesCollection)
        .doc(branchId)
        .collection(FirestoreFields.parentsCollection);
    while (true) {
      var q = parents.orderBy(FieldPath.documentId).limit(100);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final page = await q.get();
      if (page.docs.isEmpty) break;
      // Independent documents: a few at a time instead of one by one (PERF-2).
      await forEachBounded(page.docs, 8, (p) async {
        await refreshParent(
          schoolId: schoolId,
          branchId: branchId,
          parentId: p.id,
          updatedBy: updatedBy,
        );
        count++;
      });
      cursor = page.docs.last;
      if (page.docs.length < 100) break;
    }
    return count;
  }
}
