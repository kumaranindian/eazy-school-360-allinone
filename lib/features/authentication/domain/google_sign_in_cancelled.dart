/// Thrown when the user closes the Google account picker / web popup
/// without choosing an account. Deliberately not mapped to an
/// [AppFailure] — it isn't an error to show the user, just a no-op the
/// presentation layer should silently return to idle on.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}
