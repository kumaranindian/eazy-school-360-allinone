import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/config/functions_region.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/permissions/user_role.dart';
import '../../authentication/data/firebase_auth_repository.dart'
    show accessFailureFrom;
import '../../authentication/domain/login_method.dart';
import '../domain/login_access.dart';
import '../domain/login_provisioning.dart';

/// Talks to the login-access Cloud Functions. Authorization is decided on the
/// server (caller must be a school/branch admin of the record's tenant).
class FirebaseLoginAccessRepository implements LoginAccessRepository {
  final FirebaseFunctions _functions;
  FirebaseLoginAccessRepository([FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (error) {
      // Printed in release builds too, so a "Something went wrong" can be
      // diagnosed from the browser console. No payload or token is logged.
      debugPrint(
        '[loginAccess] $name region=$functionsRegion failed: '
        'code=${error.code} message=${error.message} details=${error.details}',
      );
      throw accessFailureFrom(error);
    } catch (error, stackTrace) {
      debugPrint(
        '[loginAccess] $name region=$functionsRegion failed before/while '
        'calling: ${error.runtimeType}: $error\n$stackTrace',
      );
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<LoginAccess> getAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
  }) async => LoginAccess.fromMap(
    await _call('getLoginAccess', {
      'schoolId': schoolId,
      'branchId': branchId,
      'kind': kind.wireValue,
      'id': id,
    }),
    kind,
  );

  @override
  Future<LoginAccessResult> setAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
    required bool enabled,
    required List<LoginMethod> methods,
    bool revokeSessions = false,
  }) async {
    final m = await _call('setLoginAccess', {
      'schoolId': schoolId,
      'branchId': branchId,
      'kind': kind.wireValue,
      'id': id,
      'enabled': enabled,
      'methods': [for (final x in methods) x.wireValue],
      'revokeSessions': revokeSessions,
    });
    return LoginAccessResult(
      created: m['created'] == true,
      enabled: m['enabled'] == true,
      methods: LoginMethod.listFromWire(m['methods']),
      revoked: m['revoked'] == true,
    );
  }

  @override
  Future<AccessDiagnosis> diagnose({
    required String schoolId,
    required String branchId,
    required String uid,
  }) async {
    final m = await _call('diagnoseAccess', {
      'schoolId': schoolId,
      'branchId': branchId,
      'uid': uid,
    });
    return AccessDiagnosis(
      healthy: m['healthy'] == true,
      checks: [
        for (final c in (m['checks'] as List? ?? const []))
          AccessCheck.fromMap(c as Map),
      ],
    );
  }

  @override
  Future<({int teachers, int written})> refreshTeacherAccess({
    required String schoolId,
    required String branchId,
  }) async {
    final m = await _call('refreshTeacherAccess', {
      'schoolId': schoolId,
      'branchId': branchId,
    });
    return (
      teachers: (m['teachers'] as num?)?.toInt() ?? 0,
      written: (m['written'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Map<String, UserRole>> setBranchAccess({
    required String schoolId,
    required String branchId,
    required String uid,
    required UserRole? role,
  }) async {
    final m = await _call('setBranchAccess', {
      'schoolId': schoolId,
      'branchId': branchId,
      'uid': uid,
      'role': role?.wireValue,
    });
    final raw = Map<String, dynamic>.from(
      (m['branchRoles'] as Map?) ?? const {},
    );
    final out = <String, UserRole>{};
    for (final e in raw.entries) {
      try {
        out[e.key] = UserRole.fromWireValue(e.value as String);
      } on StateError {
        // ignore unknown values
      }
    }
    return out;
  }

  @override
  Future<SchoolAuthSettings> getSchoolSettings(String schoolId) async {
    final m = await _call('getSchoolAuthSettings', {'schoolId': schoolId});
    final configured = Map<String, dynamic>.from(
      (m['configured'] as Map?) ?? const {},
    );
    return SchoolAuthSettings(
      emailPassword: m['emailPassword'] == true,
      google: m['google'] == true,
      phoneOtp: m['phoneOtp'] == true,
      phoneOtpConfigured: configured['phoneOtp'] == true,
    );
  }

  @override
  Future<int> updateSchoolSettings(
    String schoolId,
    SchoolAuthSettings next,
  ) async {
    final m = await _call('updateSchoolAuthSettings', {
      'schoolId': schoolId,
      'emailPassword': next.emailPassword,
      'google': next.google,
      'phoneOtp': next.phoneOtp,
    });
    return (m['usersUpdated'] as num?)?.toInt() ?? 0;
  }
}
