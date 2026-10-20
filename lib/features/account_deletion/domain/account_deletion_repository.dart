import 'deletion_request.dart';

/// Why a deletion call failed, in terms the screen can explain.
enum DeletionFailureKind {
  /// The sign-in is too old; the person must confirm it is them again.
  reauthRequired,

  /// Platform administrators are handled by Avail404, not self-service.
  platformAdmin,
  notCancellable,
  notFound,
  offline,
  unavailable,
}

class DeletionFailure implements Exception {
  final DeletionFailureKind kind;
  const DeletionFailure(this.kind);

  String get message => switch (kind) {
    DeletionFailureKind.reauthRequired =>
      'For your security, please confirm it is you and try again.',
    DeletionFailureKind.platformAdmin =>
      'Platform administrator accounts are handled by Avail404. Email '
          'hi@avail404.com.',
    DeletionFailureKind.notCancellable =>
      'This request has already been approved and can no longer be '
          'cancelled here. Email hi@avail404.com.',
    DeletionFailureKind.notFound => 'That request could not be found.',
    DeletionFailureKind.offline =>
      'No internet connection. Please check your network and try again.',
    DeletionFailureKind.unavailable =>
      'We could not complete that right now. Please try again later.',
  };

  @override
  String toString() => 'DeletionFailure(${kind.name})';
}

/// Records the signed-in person's own deletion requests. The server decides
/// who they are from the sign-in; nothing here names an account. Requesting
/// deletes nothing - Avail404 reviews every request first.
abstract class AccountDeletionRepository {
  /// Files a request for the signed-in account. Idempotent: an existing open
  /// request is returned instead of a second one.
  Future<DeletionRequest> request();

  /// The signed-in person's requests, newest first.
  Future<List<DeletionRequest>> mine();

  /// Withdraws a request that has not yet been approved.
  Future<DeletionRequest> cancel(String reference);
}
