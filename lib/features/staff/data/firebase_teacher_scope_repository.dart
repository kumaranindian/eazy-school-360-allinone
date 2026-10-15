import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/error_mapper.dart';
import '../domain/teacher_scope.dart';

class FirebaseTeacherScopeRepository implements TeacherScopeRepository {
  final FirebaseFirestore _firestore;
  FirebaseTeacherScopeRepository(this._firestore);

  @override
  Stream<TeacherScope?> watchScope({
    required String schoolId,
    required String branchId,
    required String userId,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('branches')
        .doc(branchId)
        .collection('teacherAccess')
        .doc(userId)
        .snapshots()
        .map((s) => s.exists ? TeacherScope.fromData(s.data()!) : null)
        .handleError((Object error, StackTrace stackTrace) {
          throw mapExceptionToFailure(error, stackTrace);
        });
  }
}
