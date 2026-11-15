import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/config/support_contact.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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

UserProfile _user(UserRole role, {String? state, PlatformRole? platformRole}) =>
    UserProfile(
      userId: _uid,
      schoolId: role == UserRole.platformAdmin ? null : 'school-1',
      branchId: role == UserRole.platformAdmin ? null : 'main',
      name: 'Grace',
      email: 'grace@example.com',
      role: role,
      status: UserStatus.active,
      schoolPaused: state != null,
      schoolAccessState: state,
      platformRole: platformRole,
    );

/// [school] is what the school document says; [state] is what the server mirrored onto the profile.
Future<String> _pump(
  WidgetTester tester, {
  required UserRole role,
  SchoolStatus school = SchoolStatus.active,
  String? state,
  PlatformRole? platformRole,
  Size size = const Size(900, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: _user(role, state: state, platformRole: platformRole),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': School(
              schoolId: 'school-1',
              name: 'Rosewood High',
              email: 'o@r.example',
              status: school,
            ),
          },
          branches: {'school-1/main': _branch},
        ),
      ),
      platformOpsRepositoryProvider.overrideWithValue(
        FakePlatformOpsRepository(stats: fakeStats()),
      ),
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
  return container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

const _schoolRoles = [
  UserRole.schoolAdmin,
  UserRole.branchAdmin,
  UserRole.teacher,
  UserRole.finance,
  UserRole.parent,
];

void main() {
  test('the support address is the fixed constant', () {
    expect(platformSupportEmail, 'admin@avail404.com');
  });

  group(
    'a school that is not active pauses every school role, with the right message',
    () {
      final messages = <String, (String, String)>{
        'INACTIVE': (
          'Account is inactive',
          'Account is inactive. Please contact admin@avail404.com.',
        ),
        'SUSPENDED': (
          'School account suspended',
          'Your school account has been suspended. Please contact admin@avail404.com for assistance.',
        ),
        'EXPIRED': (
          'School subscription expired',
          'Your school subscription has expired. Please contact admin@avail404.com.',
        ),
        'SUBSCRIPTION_NOT_STARTED': (
          'Subscription not started yet',
          'Your school subscription has not started yet. Please contact admin@avail404.com.',
        ),
        'CLOSED': (
          'School account closed',
          'Your school account has been closed. Please contact admin@avail404.com.',
        ),
      };
      for (final role in _schoolRoles) {
        for (final e in messages.entries) {
          testWidgets('${role.name} / ${e.key}', (tester) async {
            final path = await _pump(tester, role: role, state: e.key);
            expect(path, '/account-inactive');
            expect(find.text(e.value.$1), findsOneWidget);
            expect(find.textContaining(e.value.$2), findsWidgets);
            expect(
              find.byKey(const ValueKey('contact-support')),
              findsOneWidget,
            );
            expect(find.text('Sign out'), findsOneWidget);
            expect(
              find.textContaining('Incorrect email or password'),
              findsNothing,
              reason: 'never reported as bad credentials',
            );
          });
        }
      }
    },
  );

  group(
    'the school document itself pauses users even before the server mirrors it onto profiles',
    () {
      for (final role in _schoolRoles) {
        testWidgets(
          '${role.name}: a school that has just registered (INACTIVE)',
          (tester) async {
            final path = await _pump(
              tester,
              role: role,
              school: SchoolStatus.inactive,
            );
            expect(path, '/account-inactive');
            expect(find.text('Account is inactive'), findsOneWidget);
          },
        );
      }

      for (final s in [
        SchoolStatus.suspended,
        SchoolStatus.expired,
        SchoolStatus.closed,
      ]) {
        testWidgets('a ${s.name} school pauses its teacher', (tester) async {
          expect(
            await _pump(tester, role: UserRole.teacher, school: s),
            '/account-inactive',
          );
        });
      }

      testWidgets('an active school is not paused', (tester) async {
        expect(
          await _pump(tester, role: UserRole.teacher),
          isNot('/account-inactive'),
        );
      });
    },
  );

  group('the platform admin is never affected', () {
    testWidgets(
      'a platform admin signs in normally whatever any school\'s state',
      (tester) async {
        final path = await _pump(
          tester,
          role: UserRole.platformAdmin,
          platformRole: PlatformRole.owner,
          school: SchoolStatus.closed,
        );
        expect(path, '/platform');
        expect(find.text('Account is inactive'), findsNothing);
      },
    );
  });

  group('the screen stays usable on a phone at large text', () {
    for (final size in const [Size(360, 640), Size(768, 1024)]) {
      testWidgets('layout at $size', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          role: UserRole.parent,
          state: 'SUSPENDED',
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('contact-support')), findsOneWidget);
      });
    }
  });
}
