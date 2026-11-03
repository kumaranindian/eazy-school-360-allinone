import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/error_mapper.dart';
import '../../authentication/data/firebase_auth_repository.dart'
    show accessFailureFrom;
import '../domain/login_provisioning.dart';
import '../domain/school_admin.dart';

class FirebaseSchoolAdminRepository implements SchoolAdminRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  FirebaseSchoolAdminRepository(this._firestore, [FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  @override
  Future<List<SchoolAdminSummary>> list(String schoolId) async {
    try {
      // The rules let a school admin read the profiles of their own school.
      final snap = await _firestore
          .collection('users')
          .where('schoolId', isEqualTo: schoolId)
          .where('role', isEqualTo: 'SCHOOL_ADMIN')
          .limit(100)
          .get();
      final admins = [
        for (final d in snap.docs)
          SchoolAdminSummary(
            uid: d.id,
            name: (d.data()['name'] as String?) ?? '',
            email: (d.data()['email'] as String?) ?? '',
            status: (d.data()['status'] as String?) ?? '',
          ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return admins;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<CreatedSchoolAdmin> create({
    required String schoolId,
    required String name,
    required String email,
    String? phone,
    required PasswordSetup passwordSetup,
  }) async {
    try {
      final res = await _functions.httpsCallable('createSchoolAdmin').call({
        'schoolId': schoolId,
        'name': name.trim(),
        'email': email.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'passwordSetup': {
          'option': passwordSetup.option.wireValue,
          if (passwordSetup.password != null)
            'password': passwordSetup.password,
        },
      });
      final m = Map<String, dynamic>.from(res.data as Map);
      return CreatedSchoolAdmin(
        uid: m['uid'] as String,
        name: (m['name'] as String?) ?? name.trim(),
        email: (m['email'] as String?) ?? email.trim().toLowerCase(),
        passwordSet: m['passwordSet'] == true,
        tempPassword: m['tempPassword'] as String?,
      );
    } on FirebaseFunctionsException catch (error) {
      throw accessFailureFrom(error);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
