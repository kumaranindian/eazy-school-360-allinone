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
      return ValidationFailure(switch (cause) {
        'SELF_CHANGE' =>
          'You cannot change your own role or status. Ask another owner.',
        'OFFBOARDING' =>
          'This school is being offboarded. Cancel the offboarding first.',
        'ALREADY_OPEN' => 'Offboarding is already in progress for this school.',
        'SAME_PERSON' =>
          'A different owner has to approve this: you started it.',
        'NOT_REQUESTED' ||
        'NOT_OPEN' => 'That has already moved on. Refresh and try again.',
        'FINAL' => 'That record is closed and cannot be changed.',
        _ => 'That cannot be done right now.',
      });
    case 'INVALID_ARGUMENT':
      return ValidationFailure(switch (cause) {
        'emailDomain' =>
          'Only company email addresses can be platform administrators.',
        'email' => 'That email address looks invalid.',
        'name' => 'Enter the person\'s full name.',
        'reason' => 'Give a little more detail about why you need access.',
        'minutes' => 'Choose one of the listed durations.',
        'schoolName' => 'Enter the school\'s name.',
        'adminName' => 'Enter the administrator\'s full name.',
        'adminEmail' || 'schoolEmail' => 'That email address looks invalid.',
        'country' ||
        'currency' ||
        'timezone' ||
        'dateFormat' => 'Choose the school\'s country, currency and time zone.',
        'amount' => 'Enter an amount above zero.',
        'dueDate' || 'paidDate' => 'Check the date.',
        'period' => 'Say what the period is (for example Nov 2026).',
        'title' || 'body' => 'Write a title and a message.',
        'severity' => 'Choose how important the notice is.',
        'dates' => 'The end must be in the future, within 90 days.',
        'audience' => 'Choose everyone, or up to 50 schools.',
        'minBuild' => 'Build numbers must be whole numbers.',
        'message' => 'Write the message people will see.',
        'until' => 'The end time must be in the future.',
        _ => 'Check the details and try again.',
      });
    case 'INVALID_TRANSITION':
      return const ValidationFailure(
        'That request has moved on. Refresh and try again.',
      );
    case 'FEATURE_DISABLED':
      return const PermissionFailure(
        'This module is switched off for your school. Contact support.',
      );
    case 'PERMISSION_DENIED':
      return const PermissionFailure('Your platform role does not allow this.');
  }
  if (e.code == 'permission-denied') {
    return const PermissionFailure('Your platform role does not allow this.');
  }
  return mapExceptionToFailure(e, st);
}
