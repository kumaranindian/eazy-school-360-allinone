import '../../features/school_setup/domain/branch.dart';
import '../../features/school_setup/domain/school.dart';
import '../../features/users/domain/user_profile.dart';
import '../permissions/permission.dart';
import '../permissions/role_permissions.dart';
import '../permissions/user_role.dart';

/// Everything the app needs to know about "who is signed in and what
/// tenant are they acting in," assembled once after authentication and
/// read from everywhere else instead of threading `schoolId` through
/// every widget/repository call by hand.
///
/// [branch] is null for a [UserRole.schoolAdmin]/[UserRole.platformAdmin]
/// who isn't scoped to one branch — check [UserRole.isBranchScoped]
/// before assuming it's populated.
class TenantContext {
  final UserProfile user;
  final School? school;
  final Branch? branch;

  /// A platform admin looking into [school] through a support grant. Read-only:
  /// only viewing permissions apply (firestore.rules refuse every write too).
  final bool supportSession;

  const TenantContext({
    required this.user,
    this.school,
    this.branch,
    this.supportSession = false,
  });

  UserRole get role => user.role;

  static const _admissionOnly = {
    Permission.manageAdmissions,
    Permission.decideAdmissions,
  };

  bool can(Permission permission) {
    if (!RolePermissions.roleHas(role, permission)) return false;
    // The platform can switch the admission module off for a school.
    if (_admissionOnly.contains(permission) &&
        !(school?.moduleEnabled('admission') ?? true)) {
      return false;
    }
    if (!supportSession) return true;
    // Support access is look-only. The person's own things (notifications,
    // "my" screens) do not exist inside someone else's school.
    final name = permission.name;
    return permission == Permission.managePlatform ||
        (name.startsWith('view') &&
            !name.startsWith('viewOwn') &&
            permission != Permission.viewNotifications);
  }
}
