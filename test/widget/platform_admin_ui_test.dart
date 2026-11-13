import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/mfa.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_admin_providers.dart';
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

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
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

UserProfile _schoolAdmin() => const UserProfile(
  userId: _uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: 'Grace Hopper',
  email: 'grace@example.com',
  role: UserRole.schoolAdmin,
  status: UserStatus.active,
);

class _World {
  final ProviderContainer container;
  final FakeAuthRepository auth;
  final FakePlatformAdminRepository admins;
  _World(this.container, this.auth, this.admins);

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

Future<_World> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  SessionSecurity security = const SessionSecurity(
    secondFactorSignedIn: true,
    enrolledFactors: 1,
  ),
  FakePlatformAdminRepository? admins,
  Size size = const Size(1000, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final auth = FakeAuthRepository(
    signedInAs: const AppUser(uid: _uid, email: 'grace@avail404.com'),
  )..security = security;
  final repo = admins ?? FakePlatformAdminRepository();
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({_uid: profile}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
      platformAdminRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, auth, repo);
}

void main() {
  group('second-factor gate', () {
    testWidgets(
      'no second factor and none enrolled -> setup page with key and QR',
      (tester) async {
        final w = await _pump(
          tester,
          profile: _platform(PlatformRole.owner),
          security: const SessionSecurity(
            secondFactorSignedIn: false,
            enrolledFactors: 0,
          ),
        );
        expect(w.location, AppRoutes.platformMfa);
        expect(find.text('Protect your account'), findsOneWidget);
        expect(find.byKey(const ValueKey('mfa-qr')), findsOneWidget);
        expect(find.byKey(const ValueKey('mfa-secret')), findsOneWidget);
      },
    );

    testWidgets('such a platform admin cannot reach any other page', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        profile: _platform(PlatformRole.owner),
        security: const SessionSecurity(
          secondFactorSignedIn: false,
          enrolledFactors: 0,
        ),
      );
      for (final path in [
        AppRoutes.dashboard,
        AppRoutes.platformHome,
        AppRoutes.platformAdmins,
        '/students',
      ]) {
        w.container.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(w.location, AppRoutes.platformMfa, reason: path);
      }
    });

    testWidgets('a wrong first code is explained and nothing is enrolled', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        profile: _platform(PlatformRole.owner),
        security: const SessionSecurity(
          secondFactorSignedIn: false,
          enrolledFactors: 0,
        ),
      );
      w.auth.enrollmentError = const AuthFailure('That code is not correct.');
      await tester.enterText(
        find.byKey(const ValueKey('mfa-enroll-code')),
        '111111',
      );
      await tester.tap(find.byKey(const ValueKey('mfa-enroll-submit')));
      await tester.pumpAndSettle();
      expect(find.text('That code is not correct.'), findsOneWidget);
      expect(w.auth.enrollmentCodes, ['111111']);
      expect(find.text('Sign in again with your code'), findsNothing);
    });

    testWidgets('a malformed code never reaches the server', (tester) async {
      final w = await _pump(
        tester,
        profile: _platform(PlatformRole.owner),
        security: const SessionSecurity(
          secondFactorSignedIn: false,
          enrolledFactors: 0,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mfa-enroll-code')),
        '123',
      );
      await tester.tap(find.byKey(const ValueKey('mfa-enroll-submit')));
      await tester.pumpAndSettle();
      expect(find.text('The code is 6 digits'), findsOneWidget);
      expect(w.auth.enrollmentCodes, isEmpty);
    });

    testWidgets('a good first code asks the person to sign in again', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        profile: _platform(PlatformRole.owner),
        security: const SessionSecurity(
          secondFactorSignedIn: false,
          enrolledFactors: 0,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mfa-enroll-code')),
        '123456',
      );
      await tester.tap(find.byKey(const ValueKey('mfa-enroll-submit')));
      await tester.pumpAndSettle();
      expect(w.auth.enrollmentCodes, ['123456']);
      expect(find.text('Sign in again with your code'), findsOneWidget);
      expect(find.byKey(const ValueKey('mfa-sign-out')), findsOneWidget);
    });

    testWidgets(
      'enrolled but this session has no second factor -> sign in again',
      (tester) async {
        final w = await _pump(
          tester,
          profile: _platform(PlatformRole.owner),
          security: const SessionSecurity(
            secondFactorSignedIn: false,
            enrolledFactors: 1,
          ),
        );
        expect(w.location, AppRoutes.platformMfa);
        expect(find.text('Sign in again with your code'), findsOneWidget);
      },
    );
  });

  group('platform home', () {
    testWidgets(
      'a platform admin with a second factor lands on the platform home, not the school app',
      (tester) async {
        final w = await _pump(tester, profile: _platform(PlatformRole.owner));
        expect(w.location, AppRoutes.platformHome);
        expect(find.text('Welcome, Grace Hopper'), findsOneWidget);
      },
    );

    testWidgets('school pages are out of reach without a school', (
      tester,
    ) async {
      final w = await _pump(tester, profile: _platform(PlatformRole.owner));
      for (final path in [
        AppRoutes.dashboard,
        '/students',
        '/fees',
        AppRoutes.settings,
        '/',
      ]) {
        w.container.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(w.location, AppRoutes.platformHome, reason: path);
      }
    });

    testWidgets(
      'an owner sees both tools; support only branding; others none',
      (tester) async {
        await _pump(tester, profile: _platform(PlatformRole.owner));
        expect(
          find.byKey(const ValueKey('tile-platform-admins')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('tile-platform-branding')),
          findsOneWidget,
        );
      },
    );

    testWidgets('support sees branding but not administrators', (tester) async {
      await _pump(tester, profile: _platform(PlatformRole.support));
      expect(find.byKey(const ValueKey('tile-platform-admins')), findsNothing);
      expect(
        find.byKey(const ValueKey('tile-platform-branding')),
        findsOneWidget,
      );
    });

    for (final role in [PlatformRole.compliance, PlatformRole.viewer]) {
      testWidgets('${role.displayName} gets an honest "no tools yet" message', (
        tester,
      ) async {
        await _pump(tester, profile: _platform(role));
        expect(
          find.byKey(const ValueKey('tile-platform-admins')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('tile-platform-branding')),
          findsNothing,
        );
        expect(
          find.textContaining('no tools for your role yet'),
          findsOneWidget,
        );
      });
    }

    testWidgets('a school admin cannot open the platform pages', (
      tester,
    ) async {
      final w = await _pump(tester, profile: _schoolAdmin());
      for (final path in [
        AppRoutes.platformHome,
        AppRoutes.platformAdmins,
        AppRoutes.platformMfa,
      ]) {
        w.container.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(w.location, AppRoutes.dashboard, reason: path);
      }
    });
  });

  group('platform administrators page', () {
    Future<_World> openAdmins(
      WidgetTester tester, {
      PlatformRole role = PlatformRole.owner,
      FakePlatformAdminRepository? repo,
      Size size = const Size(1000, 900),
      double textScale = 1,
    }) async {
      final w = await _pump(
        tester,
        profile: _platform(role),
        admins:
            repo ??
            FakePlatformAdminRepository([
              fakeAdmin(
                uid: _uid,
                name: 'Grace Hopper',
                email: 'grace@avail404.com',
                role: PlatformRole.owner,
                self: true,
              ),
              fakeAdmin(uid: 'a1'),
              fakeAdmin(
                uid: 'a2',
                name: 'Ben Cole',
                email: 'ben@avail404.com',
                mfa: false,
                active: false,
                role: PlatformRole.viewer,
              ),
              fakeAdmin(
                uid: 'a3',
                name: 'Old Timer',
                email: 'old@avail404.com',
                role: PlatformRole.owner,
                roleAssigned: false,
              ),
            ]),
        size: size,
        textScale: textScale,
      );
      w.container.read(appRouterProvider).go(AppRoutes.platformAdmins);
      await tester.pumpAndSettle();
      return w;
    }

    testWidgets('lists people with role, two-step state and status', (
      tester,
    ) async {
      await openAdmins(tester);
      expect(find.text('Grace Hopper (you)'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Two-step not set up'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Role not assigned yet'), findsOneWidget);
      // You cannot act on yourself.
      expect(find.byKey(const ValueKey('pa-menu-$_uid')), findsNothing);
      expect(find.byKey(const ValueKey('pa-role-$_uid')), findsNothing);
    });

    testWidgets('only an owner may use it', (tester) async {
      await openAdmins(tester, role: PlatformRole.support);
      expect(
        find.text('Only a platform owner can manage administrators.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pa-add')), findsNothing);
    });

    testWidgets('adding someone sends the details and explains the next step', (
      tester,
    ) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pa-name')),
        'New Person',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pa-email')),
        'New@Avail404.com',
      );
      await tester.tap(find.byKey(const ValueKey('pa-save')));
      await tester.pumpAndSettle();
      expect(w.admins.created.single.name, 'New Person');
      expect(w.admins.created.single.role, PlatformRole.support);
      expect(find.textContaining('password-setup email'), findsOneWidget);
    });

    testWidgets('the add form validates before anything is sent', (
      tester,
    ) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pa-email')), 'nope');
      await tester.tap(find.byKey(const ValueKey('pa-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the full name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(w.admins.created, isEmpty);
    });

    testWidgets('a refusal from the server is shown in the dialog', (
      tester,
    ) async {
      final repo = FakePlatformAdminRepository([
        fakeAdmin(uid: _uid, self: true, role: PlatformRole.owner),
      ]);
      await openAdmins(tester, repo: repo);
      await tester.tap(find.byKey(const ValueKey('pa-add')));
      await tester.pumpAndSettle();
      repo.error = const ConflictFailure(
        'An account with this email address already exists.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pa-name')),
        'New Person',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pa-email')),
        'new@avail404.com',
      );
      await tester.tap(find.byKey(const ValueKey('pa-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('An account with this email address already exists.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pa-save')),
        findsOneWidget,
        reason: 'dialog stays open',
      );
    });

    testWidgets('changing a role calls the server with the new role', (
      tester,
    ) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-role-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compliance').last);
      await tester.pumpAndSettle();
      expect(w.admins.roles.single, (uid: 'a1', role: PlatformRole.compliance));
    });

    testWidgets('disabling asks first, then disables', (tester) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-menu-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable').last);
      await tester.pumpAndSettle();
      expect(find.text('Disable this administrator?'), findsOneWidget);
      expect(w.admins.statuses, isEmpty, reason: 'nothing before confirming');
      await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
      await tester.pumpAndSettle();
      expect(w.admins.statuses.single, (uid: 'a1', active: false));
    });

    testWidgets('cancelling the confirmation changes nothing', (tester) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-menu-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(w.admins.statuses, isEmpty);
    });

    testWidgets('a disabled administrator can be enabled again', (
      tester,
    ) async {
      final w = await openAdmins(tester);
      await tester.tap(find.byKey(const ValueKey('pa-menu-a2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable').last);
      await tester.pumpAndSettle();
      expect(w.admins.statuses.single, (uid: 'a2', active: true));
    });

    testWidgets('a failed list load shows a friendly message with retry', (
      tester,
    ) async {
      final repo = FakePlatformAdminRepository()
        ..error = const PermissionFailure('Only a platform owner can do this.');
      await openAdmins(tester, repo: repo);
      expect(find.text('Only a platform owner can do this.'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(768, 1024),
      Size(1400, 900),
    ]) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('platform screens fit at $size, text x$scale', (
          tester,
        ) async {
          final w = await _pump(
            tester,
            profile: _platform(PlatformRole.owner),
            admins: FakePlatformAdminRepository([
              fakeAdmin(
                uid: _uid,
                self: true,
                role: PlatformRole.owner,
                name: 'A Very Long Platform Administrator Name',
                email: 'a.very.long.email.address@avail404.com',
              ),
              fakeAdmin(uid: 'a2', mfa: false, active: false),
            ]),
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull, reason: 'home');
          w.container.read(appRouterProvider).go(AppRoutes.platformAdmins);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'admins');
          w.container.read(appRouterProvider).go(AppRoutes.platformBranding);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'branding');
        });
      }

      testWidgets('two-step setup fits at $size', (tester) async {
        await _pump(
          tester,
          profile: _platform(PlatformRole.owner),
          security: const SessionSecurity(
            secondFactorSignedIn: false,
            enrolledFactors: 0,
          ),
          size: size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
