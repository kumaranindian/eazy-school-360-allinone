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
  name: 'Rosewood High School of Excellence and Learning',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

/// Phone, tablet and desktop sizes the shell must lay out on without
/// overflowing, at normal text and at the largest scale the app allows
/// (the app caps the system text scale at 1.5, so 2.0 proves the cap holds).
Future<ProviderContainer> _pump(
  WidgetTester tester,
  UserRole role,
  Size size,
  double textScale,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
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
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper-Montgomery',
            email: 'grace@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
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

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  testWidgets('admin: shortcuts are grouped like Settings, with Coming soon', (
    tester,
  ) async {
    await _pump(tester, UserRole.schoolAdmin, const Size(1280, 900), 1.0);
    for (final group in [
      'People',
      'Academics',
      'Finance',
      'Leave',
      'Communication',
      'Administration',
      'Coming soon',
    ]) {
      // Some titles (Leave, Coming soon) also appear on a tile or badge.
      await _scrollTo(tester, find.text(group).first);
      expect(find.text(group), findsWidgets, reason: group);
    }
    // Planned modules for admins include the admin-only ones.
    for (final name in ['Transport', 'Payroll', 'Reports and analytics']) {
      await _scrollTo(tester, find.text(name));
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Coming soon'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent: own shortcuts only; no admin-only planned modules', (
    tester,
  ) async {
    await _pump(tester, UserRole.parent, const Size(1280, 900), 1.0);
    await _scrollTo(tester, find.text('My fees'));
    expect(find.text('My fees'), findsOneWidget);
    await _scrollTo(tester, find.text('Transport'));
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Payroll'), findsNothing);
    expect(find.text('Admission enquiries'), findsNothing);
    expect(find.text('Fees'), findsNothing); // the staff-side Fees entry
    expect(find.text('School profile'), findsNothing);
  });

  testWidgets('a real shortcut navigates; a Coming soon one only says so', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      UserRole.schoolAdmin,
      const Size(1280, 900),
      1.0,
    );
    final router = container.read(appRouterProvider);
    String where() => router.routerDelegate.currentConfiguration.uri.path;

    await _scrollTo(tester, find.text('Library'));
    await tester.tap(find.text('Library'));
    await tester.pump();
    expect(find.text('Library is coming soon.'), findsOneWidget);
    expect(where(), AppRoutes.dashboard);

    await _scrollTo(tester, find.text('Academic setup'));
    await tester.tap(find.text('Academic setup'));
    await tester.pumpAndSettle();
    expect(where(), AppRoutes.settings);
  });

  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('phone', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('dashboard lays out without overflow: $name, text x$scale', (
        tester,
      ) async {
        await _pump(tester, UserRole.schoolAdmin, size, scale);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -6000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
