import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

UserProfile _profile({
  required UserRole role,
  UserStatus status = UserStatus.active,
}) => UserProfile(
  userId: _uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: 'Grace Hopper',
  email: 'grace@example.com',
  role: role,
  status: status,
);

/// Pumps the real app (real router, real redirect logic) against fake
/// repositories, signed in as [_uid] with [profile] (or no profile).
Future<ProviderContainer> _pumpSignedIn(
  WidgetTester tester, {
  UserProfile? profile,
}) async {
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
        FakeUserRepository({if (profile != null) _uid: profile}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return container;
}

String _location(ProviderContainer container) => container
    .read(appRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

void main() {
  testWidgets('signed in with no profile -> create-school onboarding', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(find.text('Set up your school'), findsOneWidget);
  });

  testWidgets('signed in, DISABLED profile -> account-inactive page', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      profile: _profile(role: UserRole.teacher, status: UserStatus.disabled),
    );
    expect(find.text('Your account has been disabled'), findsOneWidget);
  });

  testWidgets(
    'signed in, INVITED profile -> account-inactive page (not a splash retry loop)',
    (tester) async {
      await _pumpSignedIn(
        tester,
        profile: _profile(role: UserRole.teacher, status: UserStatus.invited),
      );
      expect(find.text("Your account isn't active yet"), findsOneWidget);
    },
  );

  testWidgets('active school admin -> dashboard, with School and Users nav', (
    tester,
  ) async {
    final container = await _pumpSignedIn(
      tester,
      profile: _profile(role: UserRole.schoolAdmin),
    );
    expect(_location(container), AppRoutes.dashboard);
    expect(find.text('Welcome, Grace Hopper'), findsOneWidget);
    expect(find.text('School'), findsWidgets);
    expect(find.text('Users'), findsWidgets);
  });

  testWidgets('parent cannot open /school by URL — redirected to dashboard', (
    tester,
  ) async {
    final container = await _pumpSignedIn(
      tester,
      profile: _profile(role: UserRole.parent),
    );
    expect(find.text('School'), findsNothing);

    container.read(appRouterProvider).go(AppRoutes.school);
    await tester.pumpAndSettle();

    expect(_location(container), AppRoutes.dashboard);
  });

  testWidgets('teacher cannot open /school but can open /users', (
    tester,
  ) async {
    final container = await _pumpSignedIn(
      tester,
      profile: _profile(role: UserRole.teacher),
    );

    container.read(appRouterProvider).go(AppRoutes.school);
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.dashboard);

    container.read(appRouterProvider).go(AppRoutes.users);
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.users);
  });

  testWidgets('signed-in user is kept off /login', (tester) async {
    final container = await _pumpSignedIn(
      tester,
      profile: _profile(role: UserRole.teacher),
    );
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.dashboard);
  });

  testWidgets('desktop width shows the extended navigation rail', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await _pumpSignedIn(tester, profile: _profile(role: UserRole.schoolAdmin));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('mobile width shows a bottom navigation bar', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await _pumpSignedIn(tester, profile: _profile(role: UserRole.schoolAdmin));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
