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

  /// The module (platform feature) a permission belongs to, if any. A module the
  /// platform has switched off (or whose dependency is off) removes every permission
  /// in it, so navigation, routes and actions all disappear together.
  static const Map<Permission, String> _moduleOf = {
    Permission.manageAcademicSetup: 'academic',
    Permission.viewAcademicSetup: 'academic',
    Permission.manageStudentData: 'students',
    Permission.viewStudentData: 'students',
    Permission.viewParents: 'parents',
    Permission.manageAdmissions: 'admission',
    Permission.decideAdmissions: 'admission',
    Permission.manageStaff: 'staff',
    Permission.viewStaff: 'staff',
    Permission.viewOwnStaffProfile: 'staff',
    Permission.viewAttendance: 'attendance',
    Permission.markStudentAttendance: 'attendance',
    Permission.manageAttendance: 'attendance',
    Permission.viewStaffAttendance: 'attendance',
    Permission.viewOwnAttendance: 'attendance',
    Permission.viewFees: 'fees',
    Permission.manageFeeStructures: 'fees',
    Permission.assignFees: 'fees',
    Permission.issueInvoices: 'fees',
    Permission.collectPayments: 'fees',
    Permission.grantConcessions: 'fees',
    Permission.voidInvoices: 'fees',
    Permission.reversePayments: 'fees',
    Permission.viewFeeReports: 'fees',
    Permission.viewOwnChildFees: 'fees',
    Permission.viewLeave: 'leave',
    Permission.manageLeaveTypes: 'leave',
    Permission.reviewLeave: 'leave',
    Permission.adjustLeaveBalances: 'leave',
    Permission.viewOwnLeave: 'leave',
    Permission.viewLeaveCalendar: 'leave',
    Permission.viewLeaveReports: 'leave',
    Permission.viewTimetable: 'timetable',
    Permission.manageTimetable: 'timetable',
    Permission.publishTimetable: 'timetable',
    Permission.manageSubstitutions: 'timetable',
    Permission.viewOwnTimetable: 'timetable',
    Permission.viewHomework: 'homework',
    Permission.manageHomework: 'homework',
    Permission.reviewSubmissions: 'homework',
    Permission.viewOwnHomework: 'homework',
    Permission.viewAnnouncements: 'announcements',
    Permission.manageAnnouncements: 'announcements',
    Permission.viewExams: 'exams',
    Permission.manageExams: 'exams',
    Permission.enterMarks: 'exams',
    Permission.approveResults: 'exams',
    Permission.viewOwnResults: 'exams',
    Permission.viewNotifications: 'notifications',
    Permission.useMessages: 'messages',
  };

  /// Whether the platform has this module on for the school (always true for
  /// a platform admin outside a school, and for keys outside the catalogue).
  bool moduleEnabled(String feature) => school?.moduleEnabled(feature) ?? true;

  bool can(Permission permission) {
    if (!RolePermissions.roleHas(role, permission)) return false;
    final module = _moduleOf[permission];
    if (module != null && !moduleEnabled(module)) return false;
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
