/// What an Avail404 platform administrator may do. Stored on
/// `/users/{uid}.platformRole` (server-written only); enforced by Cloud
/// Functions and `firestore.rules`, mirrored here only to decide what to show.
///
/// A platform admin profile without the field is a legacy account that keeps
/// full power ([owner]) until an owner assigns a role.
enum PlatformRole {
  owner('OWNER', 'Owner', 'Everything, including managing platform admins.'),
  support(
    'SUPPORT',
    'Support',
    'School directory and support access. Cannot manage platform admins.',
  ),
  compliance(
    'COMPLIANCE',
    'Compliance',
    'Account-deletion reviews and the audit log.',
  ),
  viewer('VIEWER', 'Viewer', 'Read-only overview. No actions.');

  final String wireValue;
  final String displayName;
  final String description;

  const PlatformRole(this.wireValue, this.displayName, this.description);

  /// Null for an unknown value (grants nothing).
  static PlatformRole? tryParse(Object? value) {
    for (final r in values) {
      if (r.wireValue == value) return r;
    }
    return null;
  }
}
