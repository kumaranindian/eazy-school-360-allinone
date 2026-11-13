import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/deletion_review.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_console_providers.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/support_session_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);
const _branch = Branch(
  branchId: 'main',
  schoolId: 'school-1',
  name: 'Main campus',
  status: BranchStatus.active,
);

UserProfile _platform(PlatformRole role) => UserProfile(
  userId: _uid,
  schoolId: null,
  branchId: null,
  name: 'Grace Hopper',
  email: 'grace@avail404.com',
  role: UserRole.platformAdmin,
  status: UserStatus.active,
  platformRole: role,
);

const _schoolAdmin = UserProfile(
  userId: _uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: 'Head Teacher',
  email: 'head@rosewood.example',
  role: UserRole.schoolAdmin,
  status: UserStatus.active,
);

class _World {
  final ProviderContainer container;
  final FakePlatformConsoleRepository repo;
  _World(this.container, this.repo);

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  void go(String path) => container.read(appRouterProvider).go(path);
}

Future<_World> _pump(
  WidgetTester tester, {
  UserProfile? profile,
  PlatformRole role = PlatformRole.owner,
  FakePlatformConsoleRepository? repo,
  Size size = const Size(1000, 2600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final r = repo ?? FakePlatformConsoleRepository();
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@avail404.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({_uid: profile ?? _platform(role)}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {'school-1/main': _branch},
        ),
      ),
      platformConsoleRepositoryProvider.overrideWithValue(r),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, r);
}

/// Ends a session a test left open so no timer outlives the test.
Future<void> _close(WidgetTester tester, _World w) async {
  w.container.read(supportSessionProvider.notifier).end();
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _World w, String path) async {
  w.go(path);
  await tester.pumpAndSettle();
}

Future<void> _startSession(WidgetTester tester, _World w) async {
  await _open(tester, w, '/platform/schools/school-1');
  await tester.tap(find.byKey(const ValueKey('school-support')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('support-reason')),
    'Parent cannot see the November invoice',
  );
  await tester.tap(find.byKey(const ValueKey('support-start')));
  await tester.pumpAndSettle();
}

void main() {
  group('platform home', () {
    testWidgets(
      'owner sees schools, deletions, audit, administrators and branding',
      (tester) async {
        await _pump(tester);
        for (final k in [
          'schools',
          'deletions',
          'audit',
          'admins',
          'branding',
        ]) {
          expect(
            find.byKey(
              ValueKey('tile-platform-${k == 'admins' ? 'admins' : k}'),
            ),
            findsOneWidget,
            reason: k,
          );
        }
      },
    );

    testWidgets('support sees schools and branding only', (tester) async {
      await _pump(tester, role: PlatformRole.support);
      expect(
        find.byKey(const ValueKey('tile-platform-schools')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tile-platform-branding')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tile-platform-deletions')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('tile-platform-audit')), findsNothing);
      expect(find.byKey(const ValueKey('tile-platform-admins')), findsNothing);
    });

    testWidgets('compliance sees schools, deletions and the audit log', (
      tester,
    ) async {
      await _pump(tester, role: PlatformRole.compliance);
      expect(
        find.byKey(const ValueKey('tile-platform-deletions')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tile-platform-audit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tile-platform-branding')),
        findsNothing,
      );
    });

    testWidgets(
      'a session still open on the server can be resumed after a reload',
      (tester) async {
        final repo = FakePlatformConsoleRepository(
          initialGrants: [fakeGrant(adminUid: _uid)],
        );
        final w = await _pump(tester, repo: repo);
        expect(find.byKey(const ValueKey('active-sessions')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('resume-school-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('support-banner')), findsOneWidget);
        expect(w.location, AppRoutes.dashboard);
        await _close(tester, w);
      },
    );

    testWidgets('expired or revoked grants are not offered', (tester) async {
      final repo = FakePlatformConsoleRepository(
        initialGrants: [
          fakeGrant(adminUid: _uid, left: const Duration(minutes: -5)),
          fakeGrant(adminUid: _uid, schoolId: 'school-2', revoked: true),
        ],
      );
      await _pump(tester, repo: repo);
      expect(find.byKey(const ValueKey('active-sessions')), findsNothing);
    });
  });

  group('schools directory', () {
    FakePlatformConsoleRepository repo() => FakePlatformConsoleRepository(
      schools: [
        fakeSchool(),
        fakeSchool(
          id: 'school-2',
          name: 'Elm Academy',
          status: 'SUSPENDED',
          city: 'Madurai',
        ),
        fakeSchool(
          id: 'school-3',
          name: 'Oak Public',
          status: 'ACTIVE',
          city: 'Coimbatore',
        ),
      ],
    );

    testWidgets('lists every school with a status filter and counts', (
      tester,
    ) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformSchools);
      expect(find.text('Rosewood High'), findsOneWidget);
      expect(find.text('Elm Academy'), findsOneWidget);
      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('Suspended 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schools-filter-SUSPENDED')));
      await tester.pumpAndSettle();
      expect(find.text('Elm Academy'), findsOneWidget);
      expect(find.text('Rosewood High'), findsNothing);
    });

    testWidgets('search finds by name, city or code', (tester) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformSchools);
      await tester.enterText(
        find.byKey(const ValueKey('schools-search')),
        'coimb',
      );
      await tester.pumpAndSettle();
      expect(find.text('Oak Public'), findsOneWidget);
      expect(find.text('Rosewood High'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('schools-search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No schools match.'), findsOneWidget);
    });

    testWidgets('a school opens its overview', (tester) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformSchools);
      await tester.tap(find.byKey(const ValueKey('school-school-1')));
      await tester.pumpAndSettle();
      expect(w.location, '/platform/schools/school-1');
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Head Teacher'), findsOneWidget);
      expect(find.text('Main campus'), findsOneWidget);
    });

    testWidgets('a failed load is explained, not shown raw', (tester) async {
      final r = repo()
        ..error = const PermissionFailure(
          'Your platform role does not allow this.',
        );
      final w = await _pump(tester, repo: r);
      await _open(tester, w, AppRoutes.platformSchools);
      expect(
        find.text('Your platform role does not allow this.'),
        findsOneWidget,
      );
    });
  });

  group('school overview and support session', () {
    testWidgets('shows metadata and counts but no student records', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, '/platform/schools/school-1');
      expect(find.text('Rosewood High'), findsWidgets);
      expect(find.text('120'), findsOneWidget);
      expect(find.textContaining('Invoice question'), findsOneWidget);
    });

    for (final role in [PlatformRole.viewer, PlatformRole.compliance]) {
      testWidgets('${role.displayName} cannot start a session', (tester) async {
        final w = await _pump(tester, role: role);
        await _open(tester, w, '/platform/schools/school-1');
        expect(find.byKey(const ValueKey('school-support')), findsNothing);
        expect(
          find.text('Your platform role cannot open school data.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('the reason is validated before anything is requested', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, '/platform/schools/school-1');
      await tester.tap(find.byKey(const ValueKey('school-support')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('support-reason')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey('support-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 15'), findsOneWidget);
      expect(w.repo.requested, isEmpty);
    });

    testWidgets(
      'starting a session asks for the grant and opens the school read-only',
      (tester) async {
        final w = await _pump(tester);
        await _startSession(tester, w);
        expect(w.repo.requested.single.schoolId, 'school-1');
        expect(w.repo.requested.single.minutes, 60);
        expect(
          w.repo.requested.single.reason,
          'Parent cannot see the November invoice',
        );
        expect(w.location, AppRoutes.dashboard);
        expect(find.byKey(const ValueKey('support-banner')), findsOneWidget);
        expect(
          find.textContaining('Support session: Rosewood High'),
          findsOneWidget,
        );
        expect(find.textContaining('read-only'), findsWidgets);
        await _close(tester, w);
      },
    );

    testWidgets('inside a session only viewing permissions apply', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _startSession(tester, w);
      final tenant = w.container.read(tenantContextProvider).value!;
      expect(tenant.supportSession, isTrue);
      expect(tenant.user.schoolId, 'school-1');
      expect(tenant.can(Permission.viewStudentData), isTrue);
      expect(tenant.can(Permission.viewFees), isTrue);
      for (final p in [
        Permission.manageStudentData,
        Permission.collectPayments,
        Permission.manageSchool,
        Permission.issueInvoices,
        Permission.viewNotifications,
        Permission.viewOwnChildFees,
      ]) {
        expect(tenant.can(p), isFalse, reason: '$p');
      }
      expect(
        tenant.can(Permission.managePlatform),
        isTrue,
        reason: 'the way back to the platform pages',
      );
      await _close(tester, w);
    });

    testWidgets('a refused request shows the reason and starts nothing', (
      tester,
    ) async {
      final repo = FakePlatformConsoleRepository()
        ..requestError = const PermissionFailure(
          'Your platform role does not allow this.',
        );
      final w = await _pump(tester, repo: repo);
      await _startSession(tester, w);
      expect(
        find.text('Your platform role does not allow this.'),
        findsOneWidget,
      );
      expect(w.container.read(supportSessionProvider), isNull);
      expect(find.byKey(const ValueKey('support-banner')), findsNothing);
    });

    testWidgets(
      'End session revokes the grant and returns to the platform home',
      (tester) async {
        final w = await _pump(tester);
        await _startSession(tester, w);
        await tester.tap(find.byKey(const ValueKey('support-end')));
        await tester.pumpAndSettle();
        expect(w.repo.revoked.single.schoolId, 'school-1');
        expect(w.container.read(supportSessionProvider), isNull);
        expect(w.location, AppRoutes.platformHome);
        expect(find.byKey(const ValueKey('support-banner')), findsNothing);
      },
    );

    testWidgets(
      'the session ends by itself when the grant is revoked elsewhere',
      (tester) async {
        final w = await _pump(tester);
        await _startSession(tester, w);
        w.repo.myGrants.add([fakeGrant(adminUid: _uid, revoked: true)]);
        await tester.pumpAndSettle();
        expect(w.container.read(supportSessionProvider), isNull);
        expect(w.location, AppRoutes.platformHome);
      },
    );

    testWidgets('the session ends when time runs out', (tester) async {
      final w = await _pump(tester);
      w.container
          .read(supportSessionProvider.notifier)
          .start(
            SupportSession(
              schoolId: 'school-1',
              schoolName: 'Rosewood High',
              expiresAt: DateTime.now().add(const Duration(seconds: 2)),
            ),
          );
      // Let the school open (fake time stays under the 2 seconds).
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      w.go(AppRoutes.dashboard);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(w.location, AppRoutes.dashboard);
      expect(find.byKey(const ValueKey('support-banner')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(w.container.read(supportSessionProvider), isNull);
      expect(w.location, AppRoutes.platformHome);
    });

    testWidgets('a session already past its end never starts', (tester) async {
      final w = await _pump(tester);
      w.container
          .read(supportSessionProvider.notifier)
          .start(
            SupportSession(
              schoolId: 'school-1',
              schoolName: 'x',
              expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
            ),
          );
      await tester.pumpAndSettle();
      expect(w.container.read(supportSessionProvider), isNull);
      expect(w.location, AppRoutes.platformHome);
    });

    testWidgets('an owner can end somebody else\'s access from the overview', (
      tester,
    ) async {
      final repo = FakePlatformConsoleRepository(
        overview: fakeOverview(
          grants: [
            {
              'adminUid': 'u9',
              'adminName': 'Ben Cole',
              'adminEmail': 'ben@avail404.com',
              'reason': 'Report check',
              'expiresAtMs': DateTime.now()
                  .add(const Duration(minutes: 20))
                  .millisecondsSinceEpoch,
            },
          ],
        ),
      );
      final w = await _pump(tester, repo: repo);
      await _open(tester, w, '/platform/schools/school-1');
      expect(find.text('Ben Cole'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'End'));
      await tester.pumpAndSettle();
      expect(w.repo.revoked.single, (schoolId: 'school-1', adminUid: 'u9'));
    });
  });

  group('deletion requests', () {
    FakePlatformConsoleRepository repo() => FakePlatformConsoleRepository(
      openRequests: [
        fakeDeletion(),
        fakeDeletion(
          reference: 'DEL-BBBBBBBBBBBBBBBB',
          status: 'ACTION_REQUIRED',
          reason: 'SOLE_ADMIN',
        ),
      ],
      closedRequests: [
        fakeDeletion(reference: 'DEL-CCCCCCCCCCCCCCCC', status: 'REJECTED'),
      ],
    );

    testWidgets(
      'lists open requests with only the legal next steps and no personal data',
      (tester) async {
        final w = await _pump(tester, repo: repo());
        await _open(tester, w, AppRoutes.platformDeletions);
        expect(find.text('DEL-AAAAAAAAAAAAAAAA'), findsOneWidget);
        expect(find.textContaining('Rosewood High'), findsWidgets);
        expect(
          find.textContaining('Reason: Only school administrator'),
          findsOneWidget,
        );
        // UNDER_REVIEW
        expect(
          find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-APPROVE')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-REJECT')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-REOPEN')),
          findsNothing,
        );
        // ACTION_REQUIRED cannot be approved until reopened
        expect(
          find.byKey(const ValueKey('decide-DEL-BBBBBBBBBBBBBBBB-APPROVE')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('decide-DEL-BBBBBBBBBBBBBBBB-REOPEN')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'approving needs a confirmation and warns it cannot be undone',
      (tester) async {
        final w = await _pump(tester, repo: repo());
        await _open(tester, w, AppRoutes.platformDeletions);
        await tester.tap(
          find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-APPROVE')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('cannot be undone'), findsOneWidget);
        expect(w.repo.reviews, isEmpty);
        await tester.tap(find.byKey(const ValueKey('deletion-confirm')));
        await tester.pumpAndSettle();
        expect(w.repo.reviews.single, (
          reference: 'DEL-AAAAAAAAAAAAAAAA',
          decision: DeletionDecision.approve,
          reasonCode: null,
        ));
      },
    );

    testWidgets('rejecting can record a reason', (tester) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformDeletions);
      await tester.tap(
        find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-REJECT')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deletion-reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate request').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deletion-confirm')));
      await tester.pumpAndSettle();
      expect(w.repo.reviews.single.decision, DeletionDecision.reject);
      expect(w.repo.reviews.single.reasonCode, 'DUPLICATE');
    });

    testWidgets('cancelling the confirmation decides nothing', (tester) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformDeletions);
      await tester.tap(
        find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-APPROVE')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(w.repo.reviews, isEmpty);
    });

    testWidgets('a refusal from the server is shown', (tester) async {
      final r = repo()
        ..requestError = const ValidationFailure(
          'That request has moved on. Refresh and try again.',
        );
      final w = await _pump(tester, repo: r);
      await _open(tester, w, AppRoutes.platformDeletions);
      await tester.tap(
        find.byKey(const ValueKey('decide-DEL-AAAAAAAAAAAAAAAA-APPROVE')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deletion-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text('That request has moved on. Refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('closed requests are read-only', (tester) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformDeletions);
      await tester.tap(find.text('Closed'));
      await tester.pumpAndSettle();
      expect(find.text('DEL-CCCCCCCCCCCCCCCC'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('decide-DEL-CCCCCCCCCCCCCCCC-APPROVE')),
        findsNothing,
      );
    });

    for (final role in [PlatformRole.support, PlatformRole.viewer]) {
      testWidgets('${role.displayName} may not open the deletion queue', (
        tester,
      ) async {
        final w = await _pump(tester, role: role, repo: repo());
        await _open(tester, w, AppRoutes.platformDeletions);
        expect(
          find.text('Only owners and compliance reviewers can see these.'),
          findsOneWidget,
        );
        expect(find.text('DEL-AAAAAAAAAAAAAAAA'), findsNothing);
      });
    }
  });

  group('audit log', () {
    FakePlatformConsoleRepository repo() => FakePlatformConsoleRepository(
      audit: [
        fakeAudit(),
        fakeAudit(
          id: 'e2',
          action: 'PLATFORM_ROLE_CHANGED',
          actor: 'owner@avail404.com',
          reason: '',
        ),
      ],
    );

    testWidgets('lists entries and filters by search and action', (
      tester,
    ) async {
      final w = await _pump(tester, repo: repo());
      await _open(tester, w, AppRoutes.platformAudit);
      expect(find.text('Support access granted'), findsWidgets);
      expect(find.text('Platform role changed'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('audit-search')),
        'owner@',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('owner@avail404.com'), findsOneWidget);
      expect(find.textContaining('asha@avail404.com'), findsNothing);
    });

    testWidgets(
      'copies the visible rows as CSV, with formula-looking text neutralised',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final w = await _pump(
          tester,
          repo: FakePlatformConsoleRepository(
            audit: [
              fakeAudit(),
              fakeAudit(
                id: 'e2',
                action: 'PLATFORM_ROLE_CHANGED',
                reason: '=HYPERLINK("http://evil")',
              ),
            ],
          ),
        );
        await _open(tester, w, AppRoutes.platformAudit);
        await tester.tap(find.byKey(const ValueKey('audit-copy')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Copied 2 rows as CSV.'), findsOneWidget);
        expect(
          copied,
          startsWith(
            'When,Action,Actor,Actor role,Target,School,Reason,Result,Source',
          ),
        );
        expect(copied, contains('SUPPORT_ACCESS_GRANTED'));
        expect(
          copied,
          isNot(contains(',=HYPERLINK')),
          reason: 'a leading = would run as a formula',
        );
        expect(copied, contains("'=HYPERLINK"));
      },
    );

    testWidgets('support and viewers cannot open it', (tester) async {
      final w = await _pump(tester, role: PlatformRole.support, repo: repo());
      await _open(tester, w, AppRoutes.platformAudit);
      expect(
        find.text('Only owners and compliance reviewers can see the log.'),
        findsOneWidget,
      );
    });
  });

  group('school side: support access', () {
    testWidgets('the school admin sees who has access, why, and the history', (
      tester,
    ) async {
      final repo = FakePlatformConsoleRepository(
        initialSchoolGrants: [fakeGrant(adminUid: 'u9', adminName: 'Ben Cole')],
        initialLog: [fakeLogEntry()],
      );
      final w = await _pump(tester, profile: _schoolAdmin, repo: repo);
      await _open(tester, w, AppRoutes.settingsSupportAccess);
      expect(find.text('Ben Cole'), findsOneWidget);
      expect(find.textContaining('November invoice'), findsWidgets);
      expect(find.textContaining('was given read-only access'), findsOneWidget);
    });

    testWidgets('an expired grant is not listed as access', (tester) async {
      final repo = FakePlatformConsoleRepository(
        initialSchoolGrants: [
          fakeGrant(adminUid: 'u9', left: const Duration(minutes: -1)),
        ],
      );
      final w = await _pump(tester, profile: _schoolAdmin, repo: repo);
      await _open(tester, w, AppRoutes.settingsSupportAccess);
      expect(
        find.text('Nobody from Avail404 has access right now.'),
        findsOneWidget,
      );
      expect(
        find.text('Avail404 support has never accessed your school.'),
        findsOneWidget,
      );
    });

    testWidgets('ending access asks first, then revokes that grant', (
      tester,
    ) async {
      final repo = FakePlatformConsoleRepository(
        initialSchoolGrants: [fakeGrant(adminUid: 'u9', adminName: 'Ben Cole')],
      );
      final w = await _pump(tester, profile: _schoolAdmin, repo: repo);
      await _open(tester, w, AppRoutes.settingsSupportAccess);
      await tester.tap(find.byKey(const ValueKey('support-revoke-u9')));
      await tester.pumpAndSettle();
      expect(find.text('End this access now?'), findsOneWidget);
      expect(w.repo.revoked, isEmpty);
      await tester.tap(find.byKey(const ValueKey('support-revoke-confirm')));
      await tester.pumpAndSettle();
      expect(w.repo.revoked.single, (schoolId: 'school-1', adminUid: 'u9'));
    });

    testWidgets('keeping the access changes nothing', (tester) async {
      final repo = FakePlatformConsoleRepository(
        initialSchoolGrants: [fakeGrant(adminUid: 'u9')],
      );
      final w = await _pump(tester, profile: _schoolAdmin, repo: repo);
      await _open(tester, w, AppRoutes.settingsSupportAccess);
      await tester.tap(find.byKey(const ValueKey('support-revoke-u9')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(w.repo.revoked, isEmpty);
    });

    testWidgets('it is a school-admin screen: a teacher is sent away', (
      tester,
    ) async {
      const teacher = UserProfile(
        userId: _uid,
        schoolId: 'school-1',
        branchId: 'main',
        name: 'T',
        email: 't@x.com',
        role: UserRole.teacher,
        status: UserStatus.active,
      );
      final w = await _pump(tester, profile: teacher);
      await _open(tester, w, AppRoutes.settingsSupportAccess);
      expect(w.location, AppRoutes.dashboard);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(768, 1024),
      Size(1400, 900),
    ]) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('console screens fit at $size, text x$scale', (
          tester,
        ) async {
          final repo = FakePlatformConsoleRepository(
            schools: [
              fakeSchool(
                name: 'A School With A Rather Long Name Indeed Academy',
              ),
              fakeSchool(id: 'school-2', status: 'SUSPENDED'),
            ],
            overview: fakeOverview(
              grants: [
                {
                  'adminUid': 'u9',
                  'adminName': 'Benedict Cumberbatch-Smythe',
                  'adminEmail': 'ben@avail404.com',
                  'reason':
                      'A long reason explaining that a parent cannot see the invoice for the month of November',
                  'expiresAtMs': DateTime.now()
                      .add(const Duration(minutes: 20))
                      .millisecondsSinceEpoch,
                },
              ],
            ),
            audit: [
              fakeAudit(
                reason:
                    'A long reason explaining the access that was granted to help a parent',
              ),
            ],
            openRequests: [
              fakeDeletion(),
              fakeDeletion(
                reference: 'DEL-BBBBBBBBBBBBBBBB',
                status: 'ACTION_REQUIRED',
                reason: 'SOLE_ADMIN',
              ),
            ],
            initialSchoolGrants: [fakeGrant(adminUid: 'u9')],
          );
          final w = await _pump(
            tester,
            repo: repo,
            size: size,
            textScale: scale,
          );
          for (final path in [
            AppRoutes.platformSchools,
            '/platform/schools/school-1',
            AppRoutes.platformDeletions,
            AppRoutes.platformAudit,
          ]) {
            await _open(tester, w, path);
            expect(tester.takeException(), isNull, reason: path);
          }
        });
      }
    }

    testWidgets(
      'the school-side page and the banner fit on a phone at large text',
      (tester) async {
        final repo = FakePlatformConsoleRepository(
          initialSchoolGrants: [fakeGrant(adminUid: 'u9')],
        );
        final w = await _pump(
          tester,
          profile: _schoolAdmin,
          repo: repo,
          size: const Size(360, 640),
          textScale: 1.5,
        );
        await _open(tester, w, AppRoutes.settingsSupportAccess);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
