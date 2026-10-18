/// Domain-level failure types the presentation layer is allowed to branch
/// on. Repositories/data sources must catch source-specific exceptions
/// (`FirebaseException`, `SocketException`, ...) and map them to one of
/// these via `error_mapper.dart` — the UI should never need to know whether
/// a failure came from Firestore, Auth, or a network socket.
sealed class AppFailure {
  final String message;
  const AppFailure(this.message);
}

/// No network connectivity, or a request timed out.
final class NetworkFailure extends AppFailure {
  const NetworkFailure([
    super.message =
        'No internet connection. Please check your network and try again.',
  ]);
}

/// Sign-in failed, or the user is not signed in / their session expired.
final class AuthFailure extends AppFailure {
  const AuthFailure([super.message = "Sign-in failed. Please try again."]);
}

/// The caller is authenticated but not allowed to perform this action.
final class PermissionFailure extends AppFailure {
  const PermissionFailure([
    super.message = "You don't have permission to perform this action.",
  ]);
}

/// The requested document/resource does not exist.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure([
    super.message = 'The requested item could not be found.',
  ]);
}

/// The data changed underneath the user between loading it and saving —
/// e.g. another teacher saved the same register. Nothing was overwritten;
/// the user should reload and review.
final class ConflictFailure extends AppFailure {
  const ConflictFailure([
    super.message =
        'This was changed by someone else. Reload to see the latest and try again.',
  ]);
}

/// A multi-step save stopped part-way: [savedIds] are already stored (and
/// their revision moved on), the rest were not written. Retrying must send
/// only the rest, against the new revisions.
final class PartialSaveFailure extends AppFailure {
  final Set<String> savedIds;
  const PartialSaveFailure(super.message, this.savedIds);
}

/// Input failed validation before it was ever sent to a backend.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

/// The app build or backend project is misconfigured (Firebase not
/// initialised, sign-in provider disabled, domain not authorised, ...).
/// Not something the user can fix by retrying.
final class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure([
    super.message =
        "This feature isn't available right now because the app isn't configured correctly. Please contact support.",
  ]);
}

/// Anything else — logged with full detail, shown to the user generically.
final class UnknownFailure extends AppFailure {
  const UnknownFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// The login-access / phone-OTP backend refused a request. [reason] is the
/// stable code from the Cloud Function (see functions/index.js `fail`), never
/// shown to users — [message] is.
final class AccessPolicyFailure extends AppFailure {
  final String reason;
  final int? retryAfterSec;
  final int? attemptsLeft;
  const AccessPolicyFailure(
    super.message, {
    required this.reason,
    this.retryAfterSec,
    this.attemptsLeft,
  });
}
