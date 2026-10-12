import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/errors/error_mapper.dart';
import '../../../core/permissions/user_role.dart';
import '../domain/login_provisioning.dart';

/// Calls the `provisionLogins` Cloud Function. The server re-checks that the
/// caller is an admin of the school/branch; nothing here is trusted.
class FirebaseLoginProvisioner implements LoginProvisioner {
  static const _batchSize = 50;

  final FirebaseFunctions _functions;

  FirebaseLoginProvisioner(this._functions);

  @override
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
  }) async {
    final out = <ProvisionResult>[];
    try {
      for (var i = 0; i < ids.length; i += _batchSize) {
        final part = ids.sublist(
          i,
          i + _batchSize > ids.length ? ids.length : i + _batchSize,
        );
        final res = await _functions.httpsCallable('provisionLogins').call({
          'schoolId': schoolId,
          'branchId': branchId,
          'kind': kind.wireValue,
          'ids': part,
          if (staffRole != null) 'role': staffRole.wireValue,
          'enablePortal': enablePortal,
          'emails': {
            for (final id in part)
              if (emails[id] != null) id: emails[id],
          },
        });
        final results = (res.data as Map)['results'] as List;
        out.addAll(results.map((r) => ProvisionResult.fromMap(r as Map)));
      }
      return out;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
