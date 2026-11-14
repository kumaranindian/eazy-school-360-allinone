import 'package:eazy_school_360/core/features/feature_catalogue.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:flutter_test/flutter_test.dart';

TenantContext _tenant(UserRole role, Map<String, bool> features) =>
    TenantContext(
      user: UserProfile(
        userId: 'u',
        schoolId: 's',
        branchId: 'b',
        name: 'N',
        email: 'n@x.com',
        role: role,
        status: UserStatus.active,
      ),
      school: School(
        schoolId: 's',
        name: 'S',
        email: 's@x.com',
        status: SchoolStatus.active,
        features: features,
      ),
    );

/// Permissions that belong to no module: they never disappear with a switch.
const _moduleFree = {
  Permission.managePlatform,
  Permission.manageSchool,
  Permission.manageBranches,
  Permission.manageUsers,
  Permission.viewUsers,
  Permission.manageOwnProfile,
};

void main() {
  group('catalogue', () {
    test('keys are unique, dependencies exist, no cycles', () {
      final keys = kFeatureCatalogue.map((f) => f.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final f in kFeatureCatalogue) {
        for (final d in f.dependsOn) {
          expect(featureDef(d), isNotNull, reason: '${f.key} -> $d');
        }
        expect(dependantsOf(f.key), isNot(contains(f.key)), reason: 'cycle');
      }
    });

    test('keeps the keys that predate the catalogue', () {
      expect(featureDef('admission'), isNotNull);
      expect(featureDef('publicAdmission'), isNotNull);
    });

    test(
      'usable: missing means on; an off dependency takes dependants down',
      () {
        expect(featureUsable(const {}, 'fees'), isTrue);
        expect(featureUsable(const {'fees': false}, 'feeReminders'), isFalse);
        expect(featureUsable(const {'students': false}, 'attendance'), isFalse);
        expect(featureUsable(const {'students': false}, 'staff'), isTrue);
        expect(featureUsable(const {'academic': false}, 'attendance'), isFalse);
        expect(featureUsable(const {'whatever': false}, 'unknown-key'), isTrue);
      },
    );

    test('dependants are transitive; missing dependencies are listed', () {
      expect(dependantsOf('admission'), ['publicAdmission']);
      expect(
        dependantsOf('students'),
        containsAll([
          'parents',
          'messages',
          'fees',
          'feeReminders',
          'publicAdmission',
        ]),
      );
      expect(missingDependencies(const {'fees': false}, 'feeReminders'), [
        'fees',
      ]);
      expect(missingDependencies(const {}, 'feeReminders'), isEmpty);
    });
  });

  group('permissions follow the module switches', () {
    test('everything on: a school admin keeps what the role grants', () {
      final t = _tenant(UserRole.schoolAdmin, const {});
      expect(t.can(Permission.viewFees), isTrue);
      expect(t.can(Permission.manageAdmissions), isTrue);
    });

    test(
      'switching a module off removes ALL of its permissions, and only those',
      () {
        final t = _tenant(UserRole.schoolAdmin, const {'fees': false});
        for (final p in [
          Permission.viewFees,
          Permission.manageFeeStructures,
          Permission.assignFees,
          Permission.issueInvoices,
          Permission.collectPayments,
          Permission.grantConcessions,
          Permission.voidInvoices,
          Permission.reversePayments,
          Permission.viewFeeReports,
        ]) {
          expect(t.can(p), isFalse, reason: p.name);
        }
        expect(t.can(Permission.manageStudentData), isTrue);
        expect(t.can(Permission.manageHomework), isTrue);
      },
    );

    test(
      'a dependency off removes the dependant (students off: attendance, exams, admission)',
      () {
        final t = _tenant(UserRole.schoolAdmin, const {'students': false});
        expect(t.can(Permission.manageStudentData), isFalse);
        expect(t.can(Permission.markStudentAttendance), isFalse);
        expect(t.can(Permission.manageExams), isFalse);
        expect(t.can(Permission.manageAdmissions), isFalse);
        expect(t.can(Permission.manageStaff), isTrue);
      },
    );

    test(
      'parents lose their own module views too (fees, homework, results)',
      () {
        final t = _tenant(UserRole.parent, const {
          'fees': false,
          'homework': false,
          'exams': false,
        });
        expect(t.can(Permission.viewOwnChildFees), isFalse);
        expect(t.can(Permission.viewOwnHomework), isFalse);
        expect(t.can(Permission.viewOwnResults), isFalse);
      },
    );

    test(
      'every module permission is mapped: with ALL modules off only module-free permissions remain',
      () {
        final allOff = {for (final f in kFeatureCatalogue) f.key: false};
        for (final role in UserRole.values) {
          final t = _tenant(role, allOff);
          for (final p in Permission.values) {
            if (_moduleFree.contains(p)) continue;
            expect(
              t.can(p),
              isFalse,
              reason: '${role.name} keeps ${p.name} with every module off',
            );
          }
        }
      },
    );

    test('module-free permissions never depend on a switch', () {
      final allOff = {for (final f in kFeatureCatalogue) f.key: false};
      final on = _tenant(UserRole.schoolAdmin, const {});
      final off = _tenant(UserRole.schoolAdmin, allOff);
      for (final p in _moduleFree) {
        expect(off.can(p), on.can(p), reason: p.name);
      }
    });

    test(
      'a user outside a school (platform admin) is never limited by switches',
      () {
        const t = TenantContext(
          user: UserProfile(
            userId: 'p',
            schoolId: null,
            branchId: null,
            name: 'P',
            email: 'p@avail404.com',
            role: UserRole.platformAdmin,
            status: UserStatus.active,
          ),
        );
        expect(t.moduleEnabled('fees'), isTrue);
      },
    );
  });
}
