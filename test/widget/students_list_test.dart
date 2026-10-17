import 'package:eazy_school_360/shared/branding/page_hero.dart';
import 'package:eazy_school_360/shared/filters/directory_toolbar.dart';
import 'package:eazy_school_360/shared/layouts/directory_list.dart';
import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/student_fakes.dart';

const _uid = 'uid-1';

Future<FakeStudentListRepository> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = FakeStudentListRepository([
    fakeStudent('s1', first: 'Asha', last: 'Nair', admission: 'ADM-001'),
    fakeStudent(
      's2',
      first: 'Ravi',
      last: 'Menon',
      admission: 'ADM-002',
      status: StudentStatus.graduated,
    ),
    fakeStudent(
      's3',
      first: 'Meena',
      last: 'Pillai',
      admission: 'ADM-003',
      status: StudentStatus.left,
    ),
  ]);
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
          _uid: const UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: UserRole.branchAdmin,
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
      studentRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/students');
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets(
    'phone: stat chips with counts, search, Filters button, no row of controls',
    (tester) async {
      final repo = await _pump(tester);

      expect(find.text('Asha Nair'), findsOneWidget);
      expect(find.text('Ravi Menon'), findsNothing); // active roster by default
      expect(repo.countCalls, contains(null));
      expect(find.bySemanticsLabel('All: 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Active: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Graduated: 1'), findsOneWidget);
      expect(find.text('Filters · 1'), findsOneWidget);
      expect(find.text('By admission #'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a stat chip filters the roster by that status', (tester) async {
    final repo = await _pump(tester);
    // The chip row scrolls sideways on a phone; bring the chip into view.
    await tester.ensureVisible(find.bySemanticsLabel('Graduated: 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Graduated: 1'));
    await tester.pumpAndSettle();
    expect(repo.fetchStatuses.last, StudentStatus.graduated);
    expect(find.text('Ravi Menon'), findsOneWidget);
    expect(find.text('Asha Nair'), findsNothing);
  });

  testWidgets(
    'search waits for a pause in typing, and can switch to admission #',
    (tester) async {
      final repo = await _pump(tester);

      await tester.enterText(find.byType(TextField), 'r');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ra');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.nameSearches, isEmpty, reason: 'still typing');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.nameSearches, ['ra']);
      expect(find.text('Ravi Menon'), findsOneWidget);
      expect(find.textContaining('Filters are paused'), findsOneWidget);

      await tester.tap(find.byTooltip('Search by'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admission #').last);
      await tester.pumpAndSettle();
      expect(repo.admissionSearches, ['ra']);
    },
  );

  testWidgets('the status filter sheet changes the roster', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Filters · 1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<StudentStatus?>, 'Active'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses').last);
    await tester.pumpAndSettle();
    expect(repo.fetchStatuses.last, isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi Menon'), findsOneWidget);
  });

  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('lays out without overflow: $name, text x$scale', (
        tester,
      ) async {
        await _pump(tester, size: size, textScale: scale);
        expect(find.text('Asha Nair'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('shared directory layout', () {
    testWidgets('desktop: the same hero, toolbar and table card as staff', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      expect(find.byType(DirectoryToolbar), findsOneWidget);
      expect(find.byType(DirectoryListCard), findsOneWidget);
      expect(find.byType(DirectoryTable), findsOneWidget);
      for (final header in ['STUDENT', 'ADMISSION NO', 'CLASS', 'STATUS']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      // one 16px gutter: the hero, toolbar and list share their left edge
      final hero = tester.getRect(find.byType(PageHero));
      expect(tester.getRect(find.byType(DirectoryToolbar)).left, hero.left);
      expect(tester.getRect(find.byType(DirectoryListCard)).left, hero.left);
      expect(hero.height, lessThan(95));
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone: cards, with the footer inside the list card', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 844));
      expect(find.byType(DirectoryCard), findsWidgets);
      expect(find.byType(DirectoryTable), findsNothing);
      expect(find.textContaining('Showing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
