import 'platform_role.dart';

/// One platform administrator as the owner sees them in the list.
class PlatformAdminEntry {
  final String uid;
  final String name;
  final String email;

  /// Null when the stored role is not one this app knows.
  final PlatformRole? role;

  /// False for a legacy account that has never been given a role.
  final bool roleAssigned;
  final bool active;
  final bool mfaEnrolled;
  final String? lastSignIn;
  final bool isSelf;

  const PlatformAdminEntry({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.roleAssigned,
    required this.active,
    required this.mfaEnrolled,
    required this.lastSignIn,
    required this.isSelf,
  });

  factory PlatformAdminEntry.fromMap(Map<String, dynamic> m) =>
      PlatformAdminEntry(
        uid: m['uid'] as String,
        name: (m['name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        role: PlatformRole.tryParse(m['platformRole']),
        roleAssigned: m['roleAssigned'] == true,
        active: m['status'] == 'ACTIVE',
        mfaEnrolled: m['mfaEnrolled'] == true,
        lastSignIn: m['lastSignIn'] as String?,
        isSelf: m['isSelf'] == true,
      );
}
