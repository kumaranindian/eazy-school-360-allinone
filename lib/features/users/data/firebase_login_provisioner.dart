import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/errors/error_mapper.dart';
import '../../../core/permissions/user_role.dart';
import '../domain/login_provisioning.dart';
import '../domain/resilient_batches.dart';

/// Calls the `provisionLogins` Cloud Function. The server re-checks that the
/// caller is an admin of the school/branch; nothing here is trusted.
class FirebaseLoginProvisioner implements LoginProvisioner {
  /// Small requests: each runs well inside the function timeout, and a failed
  /// one costs only this many people a retry.
  static const batchSize = 10;
  static const concurrency = 2;

  final FirebaseFunctions _functions;
  final RetryPolicy _policy;
  final Sleeper _sleep;

  FirebaseLoginProvisioner(
    this._functions, {
    RetryPolicy policy = const RetryPolicy(),
    Sleeper? sleep,
  }) : _policy = policy,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  /// Errors worth retrying: connectivity, a busy/restarting function, rate
  /// limits. Everything else (permission, bad request) would repeat.
  static bool isTransient(Object error) =>
      error is FirebaseFunctionsException &&
      const {
        'unavailable',
        'deadline-exceeded',
        'resource-exhausted',
        'internal',
        'aborted',
        'unknown',
      }.contains(error.code);

  @override
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
    PasswordSetup? passwordSetup,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      return await runResilientBatches<String, ProvisionResult>(
        items: ids,
        batchSize: batchSize,
        concurrency: concurrency,
        onProgress: onProgress,
        isCancelled: isCancelled,
        isTransient: isTransient,
        policy: _policy,
        sleep: _sleep,
        onGaveUp: (batch) => [
          for (final id in batch)
            ProvisionResult(id: id, outcome: ProvisionOutcome.retryLater),
        ],
        call: (part) async {
          final res = await _functions.httpsCallable('provisionLogins').call({
            'schoolId': schoolId,
            'branchId': branchId,
            'kind': kind.wireValue,
            'ids': part,
            if (staffRole != null) 'role': staffRole.wireValue,
            'enablePortal': enablePortal,
            if (passwordSetup != null)
              'passwordSetup': {
                'option': passwordSetup.option.wireValue,
                if (passwordSetup.password != null)
                  'password': passwordSetup.password,
              },
            'emails': {
              for (final id in part)
                if (emails[id] != null) id: emails[id],
            },
          });
          final results = (res.data as Map)['results'] as List;
          return results.map((r) => ProvisionResult.fromMap(r as Map)).toList();
        },
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
