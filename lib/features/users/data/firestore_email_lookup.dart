import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/email_lookup.dart';

class FirestoreEmailLookup implements EmailLookup {
  final FirebaseFirestore _db;
  FirestoreEmailLookup(this._db);

  Future<bool> _exists(
    String schoolId,
    String branchId,
    String collection,
    String email,
  ) async {
    final snap = await _db
        .collection('schools')
        .doc(schoolId)
        .collection('branches')
        .doc(branchId)
        .collection(collection)
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  @override
  Future<bool> staffEmailInUse(
    String schoolId,
    String branchId,
    String email,
  ) => _exists(schoolId, branchId, 'staff', email);

  @override
  Future<bool> parentEmailInUse(
    String schoolId,
    String branchId,
    String email,
  ) => _exists(schoolId, branchId, 'parents', email);
}
