import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/academic_setup/domain/setup_status.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/setup_status_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

SetupStatus _status({required int requiredDone, bool holidays = false}) {
  const required = [
    'School Profile',
    'Branch',
    'Academic Year',
    'Classes',
    'Sections',
    'Subjects',
    'Working Days',
  ];
  return SetupStatus(
    items: [
      for (var i = 0; i < required.length; i++)
        SetupItem(
          label: required[i],
          isComplete: i < requiredDone,
          isRequired: true,
        ),
      SetupItem(
        label: 'Holiday Calendar',
        isComplete: holidays,
        isRequired: false,
      ),
    ],
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required SetupStatus status,
  Size size = const Size(1280, 900),
  double textScale = 1.0,
  UserRole role = UserRole.schoolAdmin,
}) async {
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
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {
            'school-1/main': const Branch(
              branchId: 'main',
              schoolId: 'school-1',
              name: 'Main Branch',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      setupStatusProvider.overrideWith((ref, key) async => status),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.settings);
  await tester.pumpAndSettle();
  return container;
}

String _location(ProviderContainer c) =>
    c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('shows progress, the next step, and a status on each section', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _status(requiredDone: 3),
      size: const Size(390, 844),
    );

    expect(find.text('Finish setting up'), findsOneWidget);
    expect(find.text('3 of 7 required steps done'), findsOneWidget);
    expect(find.text('Set up classes'), findsOneWidget);
    for (final group in ['Organisation', 'Academic structure', 'Calendar']) {
      await tester.scrollUntilVisible(
        find.text(group),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(group), findsOneWidget);
    }
    expect(find.text('Needs setup'), findsWidgets);
    expect(find.text('Done'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the next-step button opens that section', (tester) async {
    final container = await _pump(
      tester,
      status: _status(requiredDone: 3),
      size: const Size(390, 844),
    );
    await tester.tap(find.text('Set up classes'));
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.settingsClasses);
  });

  testWidgets('a step chip opens its section', (tester) async {
    final container = await _pump(tester, status: _status(requiredDone: 3));
    await tester.tap(find.widgetWithText(ActionChip, 'Working Days'));
    await tester.pumpAndSettle();
    expect(_location(container), AppRoutes.settingsWorkingDays);
  });

  testWidgets('when every required step is done it says so and drops the CTA', (
    tester,
  ) async {
    await _pump(tester, status: _status(requiredDone: 7, holidays: true));
    expect(find.text('Setup complete'), findsOneWidget);
    expect(find.textContaining('Set up '), findsNothing);
  });

  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('phone', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('lays out without overflow: $name at text x$scale', (
        tester,
      ) async {
        await _pump(
          tester,
          status: _status(requiredDone: 3),
          size: size,
          textScale: scale,
        );
        // Scroll to the end so every tile is laid out.
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
