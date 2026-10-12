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

  const TenantContext({required this.user, this.school, this.branch});

  UserRole get role => user.role;

  bool can(Permission permission) => RolePermissions.roleHas(role, permission);
}
