import 'dart:async';

import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/help/content/manual_content.dart';
import 'package:eazy_school_360/features/help/domain/manual_models.dart';
import 'package:eazy_school_360/features/help/domain/manual_progress_repository.dart';
import 'package:eazy_school_360/features/help/presentation/help_routes.dart';
import 'package:eazy_school_360/features/help/presentation/providers/manual_providers.dart';
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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

const _uid = 'u-1';

class _Progress implements ManualProgressRepository {
  final data = <String, ManualProgress>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<Map<String, ManualProgress>> watch(String userId) async* {
    yield Map.of(data);
    await for (final _ in _changes.stream) {
      yield Map.of(data);
    }
  }

  @override
  Future<void> save(String userId, ManualProgress progress) async {
    data[progress.guideId] = progress;
    _changes.add(null);
  }

  @override
  Future<void> reset(String userId, String guideId) async {
    data.remove(guideId);
    _changes.add(null);
  }
}

class _Auth extends FakeAuthRepository {
  _Auth()
    : super(
        signedInAs: const AppUser(uid: _uid, email: 'u@example.com'),
      );
}

List<Override> _overrides(UserRole role, _Progress progress) => [
  envConfigProvider.overrideWithValue(
    EnvConfig.forEnvironment(AppEnvironment.test),
  ),
  authRepositoryProvider.overrideWithValue(_Auth()),
  userRepositoryProvider.overrideWithValue(
    FakeUserRepository({
      _uid: UserProfile(
        userId: _uid,
        schoolId: 'school-1',
        branchId: 'main',
        name: 'Test User',
        email: 'u@example.com',
        role: role,
        status: UserStatus.active,
      ),
    }),
  ),
  schoolRepositoryProvider.overrideWithValue(
    FakeSchoolRepository(
      schools: {
        'school-1': const School(
          schoolId: 'school-1',
          name: 'Rosewood High',
          email: 'office@rosewood.example',
          status: SchoolStatus.active,
        ),
      },
      branches: {
        'school-1/main': const Branch(
          branchId: 'main',
          schoolId: 'school-1',
          name: 'Main',
          status: BranchStatus.active,
        ),
      },
    ),
  ),
  manualProgressRepositoryProvider.overrideWithValue(progress),
];

Future<void> _pump(
  WidgetTester tester,
  UserRole role,
  _Progress progress, {
  String location = '/help',
  Size size = const Size(1200, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(body: child),
        routes: helpRoutes(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(role, progress),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a teacher does not see fee guides; an admin does', (
    tester,
  ) async {
    await _pump(tester, UserRole.teacher, _Progress());
    expect(find.text('Getting started with EazySchool 360'), findsOneWidget);
    expect(find.text('Generate invoices'), findsNothing);
    expect(find.text('Apply for leave'), findsOneWidget);
  });

  testWidgets('an admin finds a guide by searching a task', (tester) async {
    await _pump(tester, UserRole.schoolAdmin, _Progress());
    await tester.enterText(find.byType(TextField), 'how to generate invoices');
    await tester.pumpAndSettle();
    expect(find.text('Generate invoices'), findsOneWidget);
    expect(
      find.text('Set up your school (first-time checklist)'),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No guide matches'), findsOneWidget);
  });

  testWidgets('steps can be completed, saved, and the guide restarted', (
    tester,
  ) async {
    final progress = _Progress();
    await _pump(
      tester,
      UserRole.schoolAdmin,
      progress,
      location: '/help/guides/payments',
    );
    expect(find.text('Collect a payment and issue a receipt'), findsWidgets);
    expect(find.textContaining('Step 1 of 6'), findsOneWidget);

    await tester.tap(find.text('Mark as done'));
    await tester.pumpAndSettle();
    expect(progress.data['payments']!.completed, {0});
    expect(find.text('Mark as not done'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 of 6'), findsOneWidget);
    expect(progress.data['payments']!.lastStep, 1);

    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as not done'));
    await tester.pumpAndSettle();
    expect(progress.data['payments']!.completed, isEmpty);

    await tester.tap(find.text('Mark as done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart this guide'));
    await tester.pumpAndSettle();
    expect(progress.data.containsKey('payments'), isFalse);
  });

  testWidgets('progress saved for an older guide version is ignored', (
    tester,
  ) async {
    final progress = _Progress()
      ..data['payments'] = const ManualProgress(
        guideId: 'payments',
        version: 99,
        completed: {0, 1, 2},
        lastStep: 2,
      );
    await _pump(
      tester,
      UserRole.schoolAdmin,
      progress,
      location: '/help/guides/payments',
    );
    expect(find.textContaining('Step 1 of 6 · 0 completed'), findsOneWidget);
  });

  testWidgets('a guide outside the role shows a message, not the steps', (
    tester,
  ) async {
    await _pump(
      tester,
      UserRole.teacher,
      _Progress(),
      location: '/help/guides/invoices',
    );
    expect(
      find.text('This guide is not available for your role.'),
      findsOneWidget,
    );
  });

  for (final (name, size) in [
    ('phone', const Size(360, 800)),
    ('tablet', const Size(820, 1000)),
    ('desktop', const Size(1400, 900)),
  ]) {
    testWidgets('home and guide lay out without overflow: $name', (
      tester,
    ) async {
      await _pump(
        tester,
        UserRole.schoolAdmin,
        _Progress(),
        size: size,
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await _pump(
        tester,
        UserRole.schoolAdmin,
        _Progress(),
        location: '/help/guides/parent-login',
        size: size,
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every guide lays out on a phone at large text', (tester) async {
    final bad = <String>[];
    for (final g in manualCatalog.guides) {
      await _pump(
        tester,
        UserRole.platformAdmin,
        _Progress(),
        location: '/help/guides/${g.id}',
        size: const Size(360, 800),
        textScale: 1.5,
      );
      if (tester.takeException() != null) bad.add(g.id);
      expect(
        find.text('This guide is not available for your role.'),
        findsNothing,
        reason: g.id,
      );
    }
    expect(bad, isEmpty);
  });

  testWidgets('a reference page lists questions without a stepper', (
    tester,
  ) async {
    await _pump(
      tester,
      UserRole.teacher,
      _Progress(),
      location: '/help/guides/faq',
    );
    expect(find.text('Frequently asked questions'), findsWidgets);
    expect(find.text('Why is a menu item missing?'), findsOneWidget);
    expect(find.text('Mark as done'), findsNothing);
  });
}
