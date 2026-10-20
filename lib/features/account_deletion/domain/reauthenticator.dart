/// Proves again that the person at the keyboard owns the signed-in account.
/// The server only accepts a deletion request from a sign-in made in the last
/// few minutes. Phone-code accounts re-verify through the normal phone-code
/// sign-in instead (same account, fresh session).
abstract class Reauthenticator {
  Future<void> withPassword(String password);
  Future<void> withGoogle();
}
