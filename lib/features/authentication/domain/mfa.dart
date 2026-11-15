/// Two-step verification (a code from an authenticator app).
///
/// Required for every platform administrator (see
/// docs/platform-admin/PLATFORM_ADMIN_PLAN.md); optional for nobody else yet.
library;

/// A password sign-in that succeeded but still needs the second factor.
/// Opaque to the UI: hand it back to `AuthRepository.completeMfaSignIn`.
abstract class MfaPending {
  const MfaPending();
}

/// Thrown by `signInWithEmailAndPassword` when the account has a second factor.
/// Not an error to show: the sign-in screen asks for the code instead.
class MfaRequiredException implements Exception {
  final MfaPending pending;
  const MfaRequiredException(this.pending);

  @override
  String toString() => 'MfaRequiredException';
}

/// What the person needs to add the account to an authenticator app.
class TotpEnrollment {
  /// The secret as text, for manual entry (grouped for reading).
  final String secretKey;

  /// `otpauth://totp/...` link; shown as a QR code.
  final String otpAuthUrl;

  /// Backend object needed to finish; opaque to the UI.
  final Object handle;

  const TotpEnrollment({
    required this.secretKey,
    required this.otpAuthUrl,
    required this.handle,
  });
}

/// How secure the CURRENT session is.
class SessionSecurity {
  /// The session was established with a second factor. This is exactly what
  /// the security rules and server callables check for platform admins.
  final bool secondFactorSignedIn;

  /// Second factors enrolled on the account.
  final int enrolledFactors;

  const SessionSecurity({
    required this.secondFactorSignedIn,
    required this.enrolledFactors,
  });

  static const none = SessionSecurity(
    secondFactorSignedIn: false,
    enrolledFactors: 0,
  );
}

/// A 6-digit code from an authenticator app.
String? validateTotpCode(String? value) {
  final v = (value ?? '').replaceAll(' ', '');
  if (v.isEmpty) return 'Enter the 6-digit code';
  if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'The code is 6 digits';
  return null;
}
