import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/features/platform_admin/domain/deletion_review.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_school.dart';
import 'package:eazy_school_360/features/platform_admin/domain/school_overview.dart';
import 'package:eazy_school_360/features/platform_admin/domain/support_access_rules.dart';
import 'package:eazy_school_360/features/platform_admin/domain/support_grant.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/platform_fakes.dart';

const _platform = UserProfile(
  userId: 'u1',
  schoolId: null,
  branchId: null,
  name: 'Grace',
  email: 'grace@avail404.com',
  role: UserRole.platformAdmin,
  status: UserStatus.active,
  platformRole: PlatformRole.owner,
);

void main() {
  group('SupportGrant', () {
    final now = DateTime(2026, 11, 13, 10);

    test('active only while unrevoked and before its end', () {
      SupportGrant g({DateTime? ends, bool revoked = false}) => SupportGrant(
        schoolId: 's',
        adminUid: 'a',
        adminName: '',
        adminEmail: '',
        reason: 'r',
        ticket: null,
        expiresAt: ends,
        revoked: revoked,
      );
      expect(
        g(ends: now.add(const Duration(minutes: 1))).isActiveAt(now),
        isTrue,
      );
      expect(
        g(ends: now).isActiveAt(now),
        isFalse,
        reason: 'the end instant is over',
      );
      expect(
        g(ends: now.subtract(const Duration(seconds: 1))).isActiveAt(now),
        isFalse,
      );
      expect(
        g(
          ends: now.add(const Duration(hours: 1)),
          revoked: true,
        ).isActiveAt(now),
        isFalse,
      );
      expect(g(ends: null).isActiveAt(now), isFalse);
    });

    test('fromMap reads a Firestore-shaped document', () {
      final g = SupportGrant.fromMap({
        'schoolId': 's1',
        'adminUid': 'a1',
        'reason': 'why',
        'expiresAt': DateTime(2026, 11, 13, 11),
        'revokedAt': null,
      });
      expect(g.schoolId, 's1');
      expect(g.revoked, isFalse);
      expect(g.expiresAt, DateTime(2026, 11, 13, 11));
      expect(
        SupportGrant.fromMap({'revokedAt': DateTime(2026)}).revoked,
        isTrue,
      );
    });
  });

  group('SupportAccessRules', () {
    test('the reason must say something real', () {
      expect(SupportAccessRules.validateReason(null), isNotNull);
      expect(SupportAccessRules.validateReason('   '), isNotNull);
      expect(
        SupportAccessRules.validateReason('too short'),
        contains('at least 15'),
      );
      expect(
        SupportAccessRules.validateReason('Parent cannot see the invoice'),
        isNull,
      );
      expect(SupportAccessRules.validateReason('x' * 501), isNotNull);
    });

    test('durations mirror the server list', () {
      expect(SupportAccessRules.minutes, [15, 30, 60, 120, 240]);
      expect(SupportAccessRules.durationLabel(15), '15 minutes');
      expect(SupportAccessRules.durationLabel(60), '1 hour');
      expect(SupportAccessRules.durationLabel(240), '4 hours');
    });
  });

  group('support session is look-only', () {
    final session = TenantContext(
      user: _platform.inSchool('s1'),
      supportSession: true,
    );
    final normal = TenantContext(user: _platform);

    test(
      'every permission except viewing is refused, and "my" screens do not exist',
      () {
        for (final p in Permission.values) {
          final granted = RolePermissions.roleHas(UserRole.platformAdmin, p);
          final allowedInSupport =
              granted &&
              (p == Permission.managePlatform ||
                  (p.name.startsWith('view') &&
                      !p.name.startsWith('viewOwn') &&
                      p != Permission.viewNotifications));
          expect(session.can(p), allowedInSupport, reason: '$p');
        }
      },
    );

    test('nothing that writes is available', () {
      const writers = [
        Permission.manageSchool,
        Permission.manageBranches,
        Permission.manageUsers,
        Permission.manageAcademicSetup,
        Permission.manageAdmissions,
        Permission.decideAdmissions,
        Permission.manageStudentData,
        Permission.manageStaff,
        Permission.markStudentAttendance,
        Permission.manageAttendance,
        Permission.manageFeeStructures,
        Permission.assignFees,
        Permission.issueInvoices,
        Permission.collectPayments,
        Permission.grantConcessions,
        Permission.voidInvoices,
        Permission.reversePayments,
        Permission.reviewLeave,
        Permission.manageTimetable,
        Permission.publishTimetable,
        Permission.manageHomework,
        Permission.manageAnnouncements,
        Permission.manageExams,
        Permission.enterMarks,
        Permission.approveResults,
        Permission.useMessages,
      ];
      for (final p in writers) {
        expect(session.can(p), isFalse, reason: '$p');
      }
    });

    test(
      'outside a support session the platform admin keeps their role permissions',
      () {
        expect(normal.can(Permission.manageSchool), isTrue);
        expect(normal.can(Permission.managePlatform), isTrue);
      },
    );

    test(
      'inSchool puts the platform admin into one school without storing anything',
      () {
        final p = _platform.inSchool('s1');
        expect(p.schoolId, 's1');
        expect(p.branchId, isNull);
        expect(p.role, UserRole.platformAdmin);
        expect(p.platformRole, PlatformRole.owner);
        expect(
          p.actsInAnyBranch,
          isTrue,
          reason: 'can look at any branch of the school',
        );
        expect(_platform.schoolId, isNull);
        expect(_platform.actsInAnyBranch, isFalse);
      },
    );
  });

  group('DeletionReviewItem decisions mirror the server lifecycle', () {
    List<DeletionDecision> of(String status) =>
        fakeDeletion(status: status).decisions;

    test('under review: approve, ask for action, reject', () {
      expect(of('UNDER_REVIEW'), [
        DeletionDecision.approve,
        DeletionDecision.requestAction,
        DeletionDecision.reject,
      ]);
    });

    test(
      'action required can only be reopened or rejected (never approved directly)',
      () {
        expect(of('ACTION_REQUIRED'), [
          DeletionDecision.reopen,
          DeletionDecision.reject,
        ]);
      },
    );

    test(
      'an approved request can still be stopped; a running one only paused',
      () {
        expect(of('APPROVED'), [
          DeletionDecision.requestAction,
          DeletionDecision.reject,
        ]);
        expect(of('PROCESSING'), [DeletionDecision.requestAction]);
        expect(of('FAILED_RETRYABLE'), [DeletionDecision.requestAction]);
      },
    );

    test('closed requests have no next step', () {
      for (final s in ['COMPLETED', 'REJECTED', 'CANCELLED', 'EXPIRED']) {
        expect(of(s), isEmpty, reason: s);
      }
    });

    test(
      'only approving is marked destructive, and every status has a label',
      () {
        expect(DeletionDecision.values.where((d) => d.isDestructive), [
          DeletionDecision.approve,
        ]);
        for (final s in [
          'PENDING_VERIFICATION',
          'UNDER_REVIEW',
          'ACTION_REQUIRED',
          'APPROVED',
          'PROCESSING',
          'FAILED_RETRYABLE',
          'COMPLETED',
          'REJECTED',
          'CANCELLED',
          'EXPIRED',
        ]) {
          expect(deletionStatusLabel(s), isNot(s), reason: s);
        }
        expect(deletionStatusLabel('SOMETHING_NEW'), 'SOMETHING_NEW');
      },
    );

    test('carries no personal fields', () {
      final item = fakeDeletion();
      expect(item.role, 'PARENT');
      expect(item.schoolName, 'Rosewood High');
    });
  });

  group('SchoolOverview.fromMap', () {
    test('reads counts, people and grants', () {
      final o = fakeOverview(
        grants: [
          {
            'adminUid': 'u9',
            'adminName': 'Ben',
            'adminEmail': 'b@a.com',
            'reason': 'r',
            'expiresAtMs': 1000,
          },
        ],
      );
      expect(o.name, 'Rosewood High');
      expect((o.students, o.staff, o.parents), (120, 14, 98));
      expect(o.branches.single.name, 'Main campus');
      expect(o.admins.single.email, 'head@rosewood.example');
      expect(o.activeGrants.single.adminUid, 'u9');
      expect(o.recentActions.single.action, 'SUPPORT_ACCESS_GRANTED');
    });

    test('tolerates a sparse server answer', () {
      final o = SchoolOverview.fromMap({
        'school': {'id': 's'},
      });
      expect(o.name, '');
      expect(o.branches, isEmpty);
      expect(o.students, 0);
    });
  });

  group('PlatformSchool and AuditEntry search', () {
    test('schools match by name, code, city or exact id', () {
      final s = fakeSchool(name: 'Rosewood High', city: 'Chennai');
      for (final q in ['rose', 'ROSEWOOD', 'chen', 'school-1', '']) {
        expect(s.matches(q), isTrue, reason: q);
      }
      expect(s.matches('madurai'), isFalse);
      expect(s.matches('school'), isTrue, reason: 'the code is SCHOOL-1');
    });

    test(
      'audit entries read as sentences and match on actor, school or reason',
      () {
        final e = fakeAudit();
        expect(e.actionLabel, 'Support access granted');
        for (final q in ['asha@', 'school-1', 'invoice', 'granted']) {
          expect(e.matches(q), isTrue, reason: q);
        }
        expect(e.matches('nobody'), isFalse);
        expect(
          const PlatformSchool(
            id: 'x',
            name: '',
            code: '',
            status: 'ACTIVE',
            city: '',
            country: '',
            createdAt: null,
          ).matches('x'),
          isTrue,
        );
      },
    );
  });
}
