import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/platform_admin_entry.dart';
import '../domain/platform_admin_repository.dart';
import '../domain/platform_role.dart';

/// [PlatformAdminRepository] backed by the owner-only callables.
class FirebasePlatformAdminRepository implements PlatformAdminRepository {
  final FirebaseFunctions _functions;

  FirebasePlatformAdminRepository([FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(r.data as Map);
    } on FirebaseFunctionsException catch (e, st) {
      throw platformFailureFrom(e, st);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<PlatformAdminEntry>> list() async {
    final out = await _call('listPlatformAdmins', const {});
    return [
      for (final a in (out['admins'] as List? ?? const []))
        PlatformAdminEntry.fromMap(Map<String, dynamic>.from(a as Map)),
    ];
  }

  @override
  Future<String> create({
    required String name,
    required String email,
    required PlatformRole role,
  }) async {
    final out = await _call('createPlatformAdmin', {
      'name': name.trim(),
      'email': email.trim(),
      'platformRole': role.wireValue,
    });
    return (out['email'] as String?) ?? email.trim().toLowerCase();
  }

  @override
  Future<void> setRole({required String uid, required PlatformRole role}) =>
      _call('setPlatformRole', {'uid': uid, 'platformRole': role.wireValue});

  @override
  Future<void> setActive({required String uid, required bool active}) => _call(
    'setPlatformAdminStatus',
    {'uid': uid, 'status': active ? 'ACTIVE' : 'DISABLED'},
  );
}

/// Plain-language messages for the platform callables' refusals. No identifiers
/// or raw server text reach the screen.
AppFailure platformFailureFrom(FirebaseFunctionsException e, StackTrace st) {
  final details = e.details;
  final reason = details is Map ? details['reason'] : null;
  final cause = details is Map ? details['cause'] : null;
  switch (reason) {
    case 'EMAIL_IN_USE':
      return const ConflictFailure(
        'An account with this email address already exists.',
      );
    case 'MFA_REQUIRED':
      return const PermissionFailure(
        'Sign in with two-step verification to do this.',
      );
    case 'NOT_FOUND':
      return const NotFoundFailure('That platform admin could not be found.');
    case 'FAILED_PRECONDITION':
      return const ValidationFailure(
        'You cannot change your own role or status. Ask another owner.',
      );
    case 'INVALID_ARGUMENT':
      return ValidationFailure(switch (cause) {
        'emailDomain' =>
          'Only company email addresses can be platform administrators.',
        'email' => 'That email address looks invalid.',
        'name' => 'Enter the person\'s full name.',
        _ => 'Check the details and try again.',
      });
    case 'PERMISSION_DENIED':
      return const PermissionFailure('Only a platform owner can do this.');
  }
  if (e.code == 'permission-denied') {
    return const PermissionFailure('Only a platform owner can do this.');
  }
  return mapExceptionToFailure(e, st);
}
