import '../../features/authentication/domain/login_method.dart';
import '../../features/users/domain/user_status.dart';

/// Why a signed-in account cannot use the app.
enum InactiveCause {
  /// Profile status is INVITED or DISABLED.
  status,

  /// An administrator switched this person's login access off.
  loginDisabled,

  /// The account is allowed, but not with the method used for this session.
  methodNotPermitted,

  /// The profile exists but its role/status is missing or unknown.
  invalidProfile,
}

/// Thrown by [TenantContextNotifier] when the signed-in user's profile
/// exists but cannot use the app: its status is not `ACTIVE` (i.e. `INVITED`
/// or `DISABLED`), login access has been switched off, or the sign-in method
/// is not permitted.
/// `firestore.rules` denies every such caller all tenant data, so the client
/// must stop here too rather than attempt reads that will fail.
///
/// Extends [Error], not `Exception`, on purpose: Riverpod's default
/// provider-retry policy retries failed rebuilds with exponential backoff
/// (up to 10 times) unless the thrown object `is Error`. An inactive
/// account won't become active by retrying, so retrying would only hold
/// the user on the splash screen for ~30 seconds.
class AccountInactiveException extends Error {
  final UserStatus status;
  final InactiveCause cause;

  /// For [InactiveCause.methodNotPermitted]: what the account may use.
  final List<LoginMethod> permitted;

  AccountInactiveException(
    this.status, {
    this.cause = InactiveCause.status,
    this.permitted = const [],
  });
}
