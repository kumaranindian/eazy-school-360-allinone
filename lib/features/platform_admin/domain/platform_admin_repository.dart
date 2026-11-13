import 'platform_admin_entry.dart';
import 'platform_role.dart';

/// Owner-only management of platform administrators. Every call is checked and
/// audited on the server; the app never writes these records itself.
abstract class PlatformAdminRepository {
  Future<List<PlatformAdminEntry>> list();

  /// Creates the account. Nobody ever sees a password: the new person is sent
  /// a password-reset email to choose their own. Returns the email used.
  Future<String> create({
    required String name,
    required String email,
    required PlatformRole role,
  });

  Future<void> setRole({required String uid, required PlatformRole role});

  Future<void> setActive({required String uid, required bool active});
}
