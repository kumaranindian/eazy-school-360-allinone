import 'app_user.dart';
import 'login_method.dart';
import 'phone_otp.dart';

/// Boundary between the authentication feature and whatever actually
/// authenticates users (Firebase Auth today). The presentation layer talks
/// only to this interface so it can be tested with a fake implementation
/// and so the backend could change without rewriting UI code.
abstract class AuthRepository {
  /// Emits the current user on every sign-in/sign-out, and `null` when
  /// signed out. Emits once immediately with the current state.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Throws an [AppFailure] (via error_mapper) on failure.
  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  /// Throws a [GoogleSignInCancelled] if the user closes the picker/popup
  /// without choosing an account, or an [AppFailure] on any real failure.
  Future<AppUser> signInWithGoogle();

  /// Throws an [AppFailure] on failure. Firebase does not reveal whether
  /// the email actually has an account — the UI shows the same
  /// "if an account exists..." message either way, so an email-enumeration
  /// probe can't distinguish a real account from a typo.
  Future<void> sendPasswordResetEmail(String email);

  /// Creates a new user account with email and password.
  /// Throws an [AppFailure] on failure.
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  });

  /// Asks the server to send a one-time code by WhatsApp to [phone]. The
  /// answer is identical for numbers that are not registered (no account
  /// enumeration). Throws an [AccessPolicyFailure] when refused (cooldown,
  /// rate limit, provider down, ...).
  Future<OtpChallenge> requestPhoneOtp(String phone);

  /// Verifies [code] on the server and, only if it is correct, signs in with
  /// the session the server mints. The client never decides success.
  Future<AppUser> verifyPhoneOtp({
    required String challengeId,
    required String code,
  });

  /// How the current session was established, or null when signed out /
  /// unknown. Used to check it against the user's permitted methods.
  Future<LoginMethod?> currentSignInMethod();

  Future<void> signOut();
}
