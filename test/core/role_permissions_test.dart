import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every UserRole has a RolePermissions entry', () {
    for (final role in UserRole.values) {
      expect(
        RolePermissions.grants.containsKey(role),
        isTrue,
        reason: '$role is missing from RolePermissions',
      );
    }
  });

  test('platformAdmin has every permission', () {
    final granted = RolePermissions.permissionsFor(UserRole.platformAdmin);
    expect(granted, Permission.values.toSet());
  });

  test(
    'parent manages their own profile and views their own children\'s fees, leave, attendance and results — nothing else',
    () {
      expect(RolePermissions.permissionsFor(UserRole.parent), {
        Permission.manageOwnProfile,
        Permission.viewOwnChildFees,
        Permission.viewOwnLeave,
        Permission.viewOwnTimetable,
        Permission.viewOwnHomework,
        Permission.viewAnnouncements,
        Permission.viewOwnResults,
        Permission.viewOwnAttendance,
        Permission.viewNotifications,
        Permission.useMessages,
      });
    },
  );

  test(
    'notifications and messages: everyone sees their notifications; '
    'finance staff and students/others do not get parent-teacher messaging',
    () {
      for (final role in UserRole.values) {
        expect(
          RolePermissions.roleHas(role, Permission.viewNotifications),
          isTrue,
          reason: '$role',
        );
      }
      for (final role in [
        UserRole.platformAdmin,
        UserRole.schoolAdmin,
        UserRole.branchAdmin,
        UserRole.teacher,
        UserRole.parent,
      ]) {
        expect(RolePermissions.roleHas(role, Permission.useMessages), isTrue);
      }
      expect(
        RolePermissions.roleHas(UserRole.finance, Permission.useMessages),
        isFalse,
      );
    },
  );

  test(
    'examinations: administrators configure, review and publish; teachers enter marks; parents view their own children\'s published results',
    () {
      for (final role in [UserRole.schoolAdmin, UserRole.branchAdmin]) {
        expect(
          RolePermissions.permissionsFor(role),
          containsAll({
            Permission.viewExams,
            Permission.manageExams,
            Permission.enterMarks,
            Permission.approveResults,
          }),
          reason: role.name,
        );
        expect(
          RolePermissions.roleHas(role, Permission.viewOwnResults),
          isFalse,
          reason: role.name,
        );
      }
      final teacher = RolePermissions.permissionsFor(UserRole.teacher);
      expect(
        teacher,
        containsAll({Permission.viewExams, Permission.enterMarks}),
      );
      expect(teacher, isNot(contains(Permission.manageExams)));
      expect(teacher, isNot(contains(Permission.approveResults)));
      final parent = RolePermissions.permissionsFor(UserRole.parent);
      expect(parent, contains(Permission.viewOwnResults));
      for (final p in [
        Permission.viewExams,
        Permission.manageExams,
        Permission.enterMarks,
        Permission.approveResults,
      ]) {
        expect(parent, isNot(contains(p)), reason: p.name);
      }
      final finance = RolePermissions.permissionsFor(UserRole.finance);
      for (final p in [
        Permission.viewExams,
        Permission.enterMarks,
        Permission.viewOwnResults,
      ]) {
        expect(finance, isNot(contains(p)), reason: p.name);
      }
    },
  );

  test(
    'homework: teachers and admins author and review; parents only view their own children\'s; finance reads announcements',
    () {
      const authoring = {
        Permission.viewHomework,
        Permission.manageHomework,
        Permission.reviewSubmissions,
        Permission.manageAnnouncements,
        Permission.viewAnnouncements,
      };
      for (final role in [
        UserRole.schoolAdmin,
        UserRole.branchAdmin,
        UserRole.teacher,
      ]) {
        expect(
          RolePermissions.permissionsFor(role),
          containsAll(authoring),
          reason: role.name,
        );
        expect(
          RolePermissions.roleHas(role, Permission.viewOwnHomework),
          isFalse,
          reason: role.name,
        );
      }
      final parent = RolePermissions.permissionsFor(UserRole.parent);
      expect(parent, contains(Permission.viewOwnHomework));
      for (final p in [
        Permission.viewHomework,
        Permission.manageHomework,
        Permission.reviewSubmissions,
        Permission.manageAnnouncements,
      ]) {
        expect(parent, isNot(contains(p)), reason: p.name);
      }
      final finance = RolePermissions.permissionsFor(UserRole.finance);
      expect(finance, contains(Permission.viewAnnouncements));
      for (final p in [
        Permission.viewHomework,
        Permission.manageHomework,
        Permission.reviewSubmissions,
        Permission.viewOwnHomework,
        Permission.manageAnnouncements,
      ]) {
        expect(finance, isNot(contains(p)), reason: p.name);
      }
    },
  );

  test(
    'leave: only admins review, adjust, configure; teachers and finance are self-service',
    () {
      for (final role in [UserRole.schoolAdmin, UserRole.branchAdmin]) {
        final p = RolePermissions.permissionsFor(role);
        expect(
          p,
          containsAll({
            Permission.viewLeave,
            Permission.manageLeaveTypes,
            Permission.reviewLeave,
            Permission.adjustLeaveBalances,
            Permission.viewLeaveReports,
          }),
        );
      }
      for (final role in [
        UserRole.teacher,
        UserRole.finance,
        UserRole.parent,
      ]) {
        final p = RolePermissions.permissionsFor(role);
        expect(p, contains(Permission.viewOwnLeave));
        for (final forbidden in [
          Permission.viewLeave,
          Permission.manageLeaveTypes,
          Permission.reviewLeave,
          Permission.adjustLeaveBalances,
          Permission.viewLeaveReports,
        ]) {
          expect(
            p,
            isNot(contains(forbidden)),
            reason: '${role.name} $forbidden',
          );
        }
      }
      // a teacher sees which students are away (calendar), nobody else below admin does
      expect(
        RolePermissions.permissionsFor(UserRole.teacher),
        contains(Permission.viewLeaveCalendar),
      );
      expect(
        RolePermissions.permissionsFor(UserRole.finance),
        isNot(contains(Permission.viewLeaveCalendar)),
      );
      expect(
        RolePermissions.permissionsFor(UserRole.parent),
        isNot(contains(Permission.viewLeaveCalendar)),
      );
    },
  );

  test(
    'schoolAdmin can manage school, branches, and users but not the platform',
    () {
      final granted = RolePermissions.permissionsFor(UserRole.schoolAdmin);
      expect(
        granted,
        containsAll({
          Permission.manageSchool,
          Permission.manageBranches,
          Permission.manageUsers,
        }),
      );
      expect(granted.contains(Permission.managePlatform), isFalse);
    },
  );

  test(
    'teacher and finance can view but not manage academic setup; parent can do neither',
    () {
      expect(
        RolePermissions.permissionsFor(UserRole.teacher),
        contains(Permission.viewAcademicSetup),
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.teacher,
        ).contains(Permission.manageAcademicSetup),
        isFalse,
      );
      expect(
        RolePermissions.permissionsFor(UserRole.finance),
        contains(Permission.viewAcademicSetup),
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.finance,
        ).contains(Permission.manageAcademicSetup),
        isFalse,
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.parent,
        ).contains(Permission.viewAcademicSetup),
        isFalse,
      );
    },
  );

  test('branchAdmin can manage academic setup within their scope', () {
    expect(
      RolePermissions.permissionsFor(UserRole.branchAdmin),
      contains(Permission.manageAcademicSetup),
    );
  });

  test(
    'teacher and finance can view but not manage student data; parent gets neither (relationship-based access instead)',
    () {
      expect(
        RolePermissions.permissionsFor(UserRole.teacher),
        contains(Permission.viewStudentData),
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.teacher,
        ).contains(Permission.manageStudentData),
        isFalse,
      );
      expect(
        RolePermissions.permissionsFor(UserRole.finance),
        contains(Permission.viewStudentData),
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.finance,
        ).contains(Permission.manageStudentData),
        isFalse,
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.parent,
        ).contains(Permission.viewStudentData),
        isFalse,
      );
    },
  );

  test('schoolAdmin and branchAdmin can manage student data', () {
    expect(
      RolePermissions.permissionsFor(UserRole.schoolAdmin),
      contains(Permission.manageStudentData),
    );
    expect(
      RolePermissions.permissionsFor(UserRole.branchAdmin),
      contains(Permission.manageStudentData),
    );
  });

  test(
    'only school-level and branch admins manage staff; teacher, finance and parent never do',
    () {
      for (final role in [
        UserRole.platformAdmin,
        UserRole.schoolAdmin,
        UserRole.branchAdmin,
      ]) {
        expect(
          RolePermissions.permissionsFor(role),
          containsAll({Permission.manageStaff, Permission.viewStaff}),
          reason: role.name,
        );
      }
      for (final role in [
        UserRole.teacher,
        UserRole.finance,
        UserRole.parent,
      ]) {
        expect(
          RolePermissions.permissionsFor(role).contains(Permission.manageStaff),
          isFalse,
          reason: role.name,
        );
      }
    },
  );

  test(
    'finance can browse staff (payroll groundwork); a teacher cannot, they only see their own profile',
    () {
      expect(
        RolePermissions.permissionsFor(UserRole.finance),
        contains(Permission.viewStaff),
      );
      expect(
        RolePermissions.permissionsFor(
          UserRole.teacher,
        ).contains(Permission.viewStaff),
        isFalse,
      );
      expect(
        RolePermissions.permissionsFor(UserRole.teacher),
        contains(Permission.viewOwnStaffProfile),
      );
    },
  );

  test('parent has no staff access of any kind', () {
    final parent = RolePermissions.permissionsFor(UserRole.parent);
    expect(parent.contains(Permission.manageStaff), isFalse);
    expect(parent.contains(Permission.viewStaff), isFalse);
    expect(parent.contains(Permission.viewOwnStaffProfile), isFalse);
  });

  test('roleHas is consistent with permissionsFor', () {
    for (final role in UserRole.values) {
      for (final permission in Permission.values) {
        expect(
          RolePermissions.roleHas(role, permission),
          RolePermissions.permissionsFor(role).contains(permission),
        );
      }
    }
  });

  test('UserRole wireValue round-trips through fromWireValue', () {
    for (final role in UserRole.values) {
      expect(UserRole.fromWireValue(role.wireValue), role);
    }
  });
}
