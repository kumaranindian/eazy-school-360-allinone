import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../../core/config/functions_region.dart';
import '../domain/account_deletion_repository.dart';
import '../domain/deletion_request.dart';

/// Talks to the account-deletion Cloud Functions. Who the caller is, and
/// whether they may ask, is decided on the server from the verified sign-in;
/// nothing identifying is sent from here.
class FirebaseAccountDeletionRepository implements AccountDeletionRepository {
  final FirebaseFunctions _functions;
  FirebaseAccountDeletionRepository([FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  Future<Object?> _call(String name, [Map<String, dynamic>? data]) async {
    try {
      final res = await _functions.httpsCallable(name).call(data);
      return res.data;
    } on FirebaseFunctionsException catch (error) {
      // Code and reason only: the message can carry details, and nothing here
      // should write personal data to a log.
      final reason = _reasonOf(error);
      debugPrint('[accountDeletion] $name failed: ${error.code} $reason');
      throw DeletionFailure(kindOf(error.code, reason));
    } catch (error) {
      debugPrint('[accountDeletion] $name failed: ${error.runtimeType}');
      throw const DeletionFailure(DeletionFailureKind.unavailable);
    }
  }

  static String? _reasonOf(FirebaseFunctionsException error) {
    final d = error.details;
    return d is Map ? d['reason'] as String? : null;
  }

  @visibleForTesting
  static DeletionFailureKind kindOf(String code, String? reason) {
    switch (reason) {
      case 'REAUTH_REQUIRED':
        return DeletionFailureKind.reauthRequired;
      case 'PLATFORM_ADMIN':
        return DeletionFailureKind.platformAdmin;
      case 'NOT_CANCELLABLE':
        return DeletionFailureKind.notCancellable;
      case 'NOT_FOUND':
        return DeletionFailureKind.notFound;
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return DeletionFailureKind.offline;
    }
    return DeletionFailureKind.unavailable;
  }

  @override
  Future<DeletionRequest> request() async {
    final data = await _call('requestAccountDeletion', {'confirm': true});
    return DeletionRequest.fromMap(data as Map);
  }

  @override
  Future<List<DeletionRequest>> mine() async {
    final data = await _call('getMyDeletionRequests');
    return [
      for (final item in (data as List? ?? const []))
        DeletionRequest.fromMap(item as Map),
    ];
  }

  @override
  Future<DeletionRequest> cancel(String reference) async {
    final data = await _call('cancelAccountDeletion', {'reference': reference});
    return DeletionRequest.fromMap(data as Map);
  }
}
