import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/parent_counter.dart';

class FirebaseParentCounter implements ParentCounter {
  final FirebaseFirestore _firestore;
  FirebaseParentCounter(this._firestore);

  @override
  Future<int> countParents({
    required String schoolId,
    required String branchId,
    ActivationStatus? status,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection(FirestoreFields.schoolsCollection)
          .doc(schoolId)
          .collection(FirestoreFields.branchesCollection)
          .doc(branchId)
          .collection(FirestoreFields.parentsCollection);
      if (status != null) {
        q = q.where(FirestoreFields.status, isEqualTo: status.wireValue);
      }
      return (await q.count().get()).count ?? 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
