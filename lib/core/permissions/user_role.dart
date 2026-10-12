/// Platform-wide roles. The Firestore string value (`.wireValue`) is what
/// is stored on `/users/{uid}.role` and what `firestore.rules` compares
/// against — keep the two in sync if this enum ever changes.
///
/// Adding a role: add the enum value + its `.wireValue`, add it to
/// [RolePermissions.grants] in `role_permissions.dart`, and add it to any
/// Firestore rule that enumerates roles explicitly (see
/// MULTI_TENANT_GUIDE.md → "How to add a new role").
enum UserRole {
  platformAdmin,
  schoolAdmin,
  branchAdmin,
  teacher,
  finance,
  parent;

  static const Map<UserRole, String> _wireValues = {
    UserRole.platformAdmin: 'PLATFORM_ADMIN',
    UserRole.schoolAdmin: 'SCHOOL_ADMIN',
    UserRole.branchAdmin: 'BRANCH_ADMIN',
    UserRole.teacher: 'TEACHER',
    UserRole.finance: 'FINANCE',
    UserRole.parent: 'PARENT',
  };

  /// The exact string stored in Firestore — matches `firestore.rules`.
  String get wireValue => _wireValues[this]!;

  static UserRole fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case UserRole.platformAdmin:
        return 'Platform Admin';
      case UserRole.schoolAdmin:
        return 'School Admin';
      case UserRole.branchAdmin:
        return 'Branch Admin';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.finance:
        return 'Finance';
      case UserRole.parent:
        return 'Parent';
    }
  }

  bool get isSchoolScoped => this != UserRole.platformAdmin;
  bool get isBranchScoped =>
      this != UserRole.platformAdmin && this != UserRole.schoolAdmin;
}
