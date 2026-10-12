import '../../features/users/domain/user_status.dart';

/// Thrown by [TenantContextNotifier] when the signed-in user's profile
/// exists but is not `ACTIVE` (i.e. `INVITED` or `DISABLED`).
/// `firestore.rules` denies every non-active caller all tenant data, so the
/// client must stop here too rather than attempt reads that will fail.
///
/// Extends [Error], not `Exception`, on purpose: Riverpod's default
/// provider-retry policy retries failed rebuilds with exponential backoff
/// (up to 10 times) unless the thrown object `is Error`. An inactive
/// account won't become active by retrying, so retrying would only hold
/// the user on the splash screen for ~30 seconds.
class AccountInactiveException extends Error {
  final UserStatus status;

  AccountInactiveException(this.status);
}
