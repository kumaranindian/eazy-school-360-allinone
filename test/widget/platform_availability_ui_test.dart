import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_models.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_console_providers.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_ops_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/platform_ops_fakes.dart';

const _uid = 'uid-1';
const _branch = Branch(
  branchId: 'main',
  schoolId: 'school-1',
  name: 'Main',
  status: BranchStatus.active,
);
School _school({Map<String, bool> features = const {}}) => School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'o@r.example',
  status: SchoolStatus.active,
  features: features,
);

UserProfile _user(
  UserRole role, {
  bool paused = false,
  PlatformRole? platformRole,
}) => UserProfile(
  userId: _uid,
  schoolId: role == UserRole.platformAdmin ? null : 'school-1',
  branchId: role == UserRole.platformAdmin ? null : 'main',
  name: 'Grace Hopper',
  email: 'grace@example.com',
  role: role,
  status: UserStatus.active,
  schoolPaused: paused,
  platformRole: platformRole,
);

class _W {
  final ProviderContainer container;
  final FakePlatformOpsRepository ops;
  _W(this.container, this.ops);
  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

/// Runs [body] with the platform overridden and ALWAYS restores it before the
/// test ends (Flutter checks debug variables before tearDown runs).
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<_W> _pump(
  WidgetTester tester, {
  UserProfile? profile,
  AppRequirements requirements = AppRequirements.none,
  List<SchoolNotice> notices = const [],
  Map<String, bool> features = const {},
  Size size = const Size(1000, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ops = FakePlatformOpsRepository(stats: fakeStats())
    ..initialRequirements = requirements
    ..initialNotices = notices;
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: profile == null
              ? null
              : const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({if (profile != null) _uid: profile}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school(features: features)},
          branches: {'school-1/main': _branch},
        ),
      ),
      platformOpsRepositoryProvider.overrideWithValue(ops),
      platformConsoleRepositoryProvider.overrideWithValue(
        FakePlatformConsoleRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _W(container, ops);
}

AppRequirements _maintenance({
  DateTime? until,
  String message = 'Back at 6am',
}) => AppRequirements(
  maintenanceOn: true,
  maintenanceMessage: message,
  maintenanceUntil: until,
);

void main() {
  group('maintenance mode', () {
    testWidgets(
      'school users see the message instead of the app, and can sign out',
      (tester) async {
        await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          requirements: _maintenance(),
        );
        expect(
          find.byKey(const ValueKey('maintenance-screen')),
          findsOneWidget,
        );
        expect(find.text('Back at 6am'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('maintenance-sign-out')),
          findsOneWidget,
        );
      },
    );

    for (final r in [UserRole.teacher, UserRole.parent]) {
      testWidgets('${r.name}s are paused too', (tester) async {
        await _pump(tester, profile: _user(r), requirements: _maintenance());
        expect(
          find.byKey(const ValueKey('maintenance-screen')),
          findsOneWidget,
        );
      });
    }

    testWidgets('a platform admin is never blocked and is reminded it is on', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        profile: _user(
          UserRole.platformAdmin,
          platformRole: PlatformRole.owner,
        ),
        requirements: _maintenance(),
      );
      expect(find.byKey(const ValueKey('maintenance-screen')), findsNothing);
      expect(find.byKey(const ValueKey('maintenance-strip')), findsOneWidget);
      expect(find.textContaining('school users are paused'), findsOneWidget);
      expect(w.location, '/platform');
    });

    testWidgets('signed out, the sign-in screen stays usable with a notice', (
      tester,
    ) async {
      await _pump(tester, requirements: _maintenance());
      expect(find.byKey(const ValueKey('maintenance-screen')), findsNothing);
      expect(find.byKey(const ValueKey('maintenance-strip')), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('a window whose end time has passed no longer blocks', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: _user(UserRole.schoolAdmin),
        requirements: _maintenance(
          until: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      expect(find.byKey(const ValueKey('maintenance-screen')), findsNothing);
    });

    testWidgets('switching it on or off takes effect live', (tester) async {
      final w = await _pump(tester, profile: _user(UserRole.schoolAdmin));
      expect(find.byKey(const ValueKey('maintenance-screen')), findsNothing);
      w.ops.requirements.add(_maintenance());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('maintenance-screen')), findsOneWidget);
      w.ops.requirements.add(AppRequirements.none);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('maintenance-screen')), findsNothing);
    });
  });

  group('minimum app version', () {
    testWidgets(
      'an Android build below the minimum must update (the footer says which)',
      (tester) async {
        await _onPlatform(TargetPlatform.android, () async {
          await _pump(
            tester,
            profile: _user(UserRole.schoolAdmin),
            requirements: const AppRequirements(minBuildAndroid: 99),
          );
          expect(find.byKey(const ValueKey('update-required')), findsOneWidget);
          expect(find.textContaining('v1.1.0'), findsOneWidget);
        });
      },
    );

    testWidgets('a build at or above the minimum is fine', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          requirements: const AppRequirements(minBuildAndroid: 13),
        );
        expect(find.byKey(const ValueKey('update-required')), findsNothing);
      });
    });

    testWidgets('the iOS minimum does not affect Android', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          requirements: const AppRequirements(minBuildIos: 99),
        );
        expect(find.byKey(const ValueKey('update-required')), findsNothing);
      });
    });

    testWidgets('on iOS it blocks even the signed-out screens', (tester) async {
      await _onPlatform(TargetPlatform.iOS, () async {
        await _pump(
          tester,
          requirements: const AppRequirements(minBuildIos: 99),
        );
        expect(find.byKey(const ValueKey('update-required')), findsOneWidget);
      });
    });
  });

  group('notices from Avail404', () {
    testWidgets(
      'a school administrator sees live notices and can dismiss them',
      (tester) async {
        await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          notices: [fakeSchoolNotice()],
        );
        expect(find.text('Planned maintenance'), findsOneWidget);
        expect(find.text('Read-only on Sunday 2-4am.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('notice-dismiss-n1')));
        await tester.pumpAndSettle();
        expect(find.text('Planned maintenance'), findsNothing);
      },
    );

    testWidgets('branch administrators see them too', (tester) async {
      await _pump(
        tester,
        profile: _user(UserRole.branchAdmin),
        notices: [fakeSchoolNotice()],
      );
      expect(find.text('Planned maintenance'), findsOneWidget);
    });

    for (final r in [UserRole.teacher, UserRole.finance, UserRole.parent]) {
      testWidgets('a ${r.name} does not see them', (tester) async {
        await _pump(tester, profile: _user(r), notices: [fakeSchoolNotice()]);
        expect(find.text('Planned maintenance'), findsNothing);
      });
    }

    testWidgets('withdrawn, expired and not-yet-started notices are hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: _user(UserRole.schoolAdmin),
        notices: [
          fakeSchoolNotice(id: 'a', title: 'Withdrawn one', withdrawn: true),
          fakeSchoolNotice(
            id: 'b',
            title: 'Expired one',
            ends: const Duration(minutes: -1),
          ),
          fakeSchoolNotice(
            id: 'c',
            title: 'Future one',
            starts: const Duration(hours: 3),
            ends: const Duration(days: 1),
          ),
          fakeSchoolNotice(id: 'd', title: 'Live one'),
        ],
      );
      expect(find.text('Live one'), findsOneWidget);
      for (final t in ['Withdrawn one', 'Expired one', 'Future one']) {
        expect(find.text(t), findsNothing, reason: t);
      }
    });

    testWidgets('a new notice appears live', (tester) async {
      final w = await _pump(tester, profile: _user(UserRole.schoolAdmin));
      expect(find.text('Planned maintenance'), findsNothing);
      w.ops.schoolNotices.add([fakeSchoolNotice()]);
      await tester.pumpAndSettle();
      expect(find.text('Planned maintenance'), findsOneWidget);
    });

    testWidgets('at most two show at once, on a phone too', (tester) async {
      await _pump(
        tester,
        profile: _user(UserRole.schoolAdmin),
        size: const Size(360, 700),
        notices: [
          for (var i = 0; i < 4; i++)
            fakeSchoolNotice(
              id: 'n$i',
              title: 'Notice $i',
              starts: Duration(minutes: -10 + i),
            ),
        ],
      );
      expect(find.textContaining('Notice '), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('a suspended school', () {
    testWidgets('its users get a clear "paused" screen with only sign out', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        profile: _user(UserRole.teacher, paused: true),
      );
      expect(find.text("Your school's access is paused"), findsOneWidget);
      expect(
        find.textContaining(
          'contact your school administrator or Avail404 support',
        ),
        findsOneWidget,
      );
      expect(find.text('Sign out'), findsOneWidget);
      expect(w.location, '/account-inactive');
    });

    for (final r in [UserRole.schoolAdmin, UserRole.parent]) {
      testWidgets('a paused ${r.name} gets the same screen', (tester) async {
        final w = await _pump(tester, profile: _user(r, paused: true));
        expect(w.location, '/account-inactive');
      });
    }

    testWidgets('a school that is not suspended works normally', (
      tester,
    ) async {
      final w = await _pump(tester, profile: _user(UserRole.schoolAdmin));
      expect(w.location, isNot('/account-inactive'));
    });
  });

  group('platform module switches', () {
    testWidgets(
      'with admission off the admission permissions are gone, nothing else changes',
      (tester) async {
        final w = await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          features: {'admission': false},
        );
        final t = w.container.read(tenantContextProvider).value!;
        expect(t.can(Permission.manageAdmissions), isFalse);
        expect(t.can(Permission.decideAdmissions), isFalse);
        expect(t.can(Permission.manageStudentData), isTrue);
        expect(t.can(Permission.viewFees), isTrue);
      },
    );

    for (final f in [
      const <String, bool>{},
      {'admission': true},
      {'publicAdmission': false},
    ]) {
      testWidgets('switches $f leave admission available', (tester) async {
        final w = await _pump(
          tester,
          profile: _user(UserRole.schoolAdmin),
          features: f,
        );
        expect(
          w.container
              .read(tenantContextProvider)
              .value!
              .can(Permission.manageAdmissions),
          isTrue,
        );
      });
    }
  });
}
