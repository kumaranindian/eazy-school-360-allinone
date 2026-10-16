import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
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
import '../support/school_year_fakes.dart';
import '../support/staff_fakes.dart';

SchoolAcademicYear _sy(String id, String name, {bool archived = false}) =>
    SchoolAcademicYear(
      schoolYearId: id,
      schoolId: 's1',
      name: name,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 3, 31),
      status: archived ? SchoolYearStatus.archived : SchoolYearStatus.active,
    );

Branch _b(String id) => Branch(
  branchId: id,
  schoolId: 's1',
  name: '${id[0].toUpperCase()}${id.substring(1)} Campus',
  status: BranchStatus.active,
);

Future<({ProviderContainer container, FakeSchoolYearRepository years})> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.schoolAdmin,
  Size size = const Size(1000, 900),
  double textScale = 1.0,
  FakeSchoolYearRepository? years,
  List<AcademicYear> branchYears = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final fakeYears =
      years ??
      FakeSchoolYearRepository(
        years: [
          _sy('y26', '2026-27'),
          _sy('y25', '2025-26'),
          _sy('old', '2019-20', archived: true),
        ],
        opened: {
          'y25': {'north', 'south'},
          'y26': {'north'},
        },
      );
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          'u1': UserProfile(
            userId: 'u1',
            schoolId: 's1',
            branchId: 'north',
            name: 'Asha',
            email: 'a@x.example',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: const {
            's1': School(
              schoolId: 's1',
              name: 'Rosewood',
              email: 'o@r.example',
              status: SchoolStatus.active,
            ),
          },
          branches: {
            's1/north': _b('north'),
            's1/south': _b('south'),
            's1/east': _b('east'),
          },
        ),
      ),
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(years: branchYears),
      ),
      schoolYearRepositoryProvider.overrideWithValue(fakeYears),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return (container: container, years: fakeYears);
}

void main() {
  group('School years page', () {
    testWidgets('lists the years with how many branches have opened each', (
      tester,
    ) async {
      final w = await _pump(tester);
      w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
      await tester.pumpAndSettle();
      expect(find.text('2026-27'), findsOneWidget);
      expect(find.text('Open in 1 of 3 branches'), findsOneWidget);
      expect(find.text('Open in 2 of 3 branches'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'opening a year in branches skips the ones that already have it',
      (tester) async {
        final w = await _pump(tester);
        w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
        await tester.pumpAndSettle();
        // only the 2026-27 card offers it (2025-26 is open in 2 of 3, also offers);
        await tester.tap(find.text('Open in branches').first);
        await tester.pumpAndSettle();
        expect(find.text('Already open'), findsWidgets);
        await tester.tap(find.textContaining('Open in 2 branches'));
        await tester.pumpAndSettle();
        expect(w.years.openCalls, hasLength(1));
        expect(w.years.openCalls.single.branches.toSet(), {'south', 'east'});
      },
    );

    testWidgets(
      'a branch that refuses is reported and does not close the dialog',
      (tester) async {
        final w = await _pump(
          tester,
          years: FakeSchoolYearRepository(
            years: [_sy('y26', '2026-27')],
            refusing: {'east'},
          ),
        );
        w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open in branches'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Open in 3 branches'));
        await tester.pumpAndSettle();
        expect(find.text('You do not have access.'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('archive and restore call the repository', (tester) async {
      final w = await _pump(tester);
      w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').first);
      await tester.pumpAndSettle();
      expect(w.years.archiveCalls, [
        (yearId: 'old', archived: false),
        (yearId: 'y26', archived: true),
      ]);
    });

    testWidgets('adding a school year validates and saves', (tester) async {
      final w = await _pump(tester);
      w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add school year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(w.years.created, isEmpty);
      expect(find.text('Name is required.'), findsOneWidget);
    });

    testWidgets('only a school admin sees it', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
      await tester.pumpAndSettle();
      expect(find.text('Add school year'), findsNothing);
      expect(
        find.text('Only a school administrator can manage school years.'),
        findsOneWidget,
      );
    });

    for (final (name, size, scale) in [
      ('small phone', const Size(320, 640), 1.5),
      ('tablet', const Size(820, 1180), 1.0),
    ]) {
      testWidgets('lays out without overflow: $name', (tester) async {
        final w = await _pump(tester, size: size, textScale: scale);
        w.container.read(appRouterProvider).go(AppRoutes.settingsSchoolYears);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Academic years page (branch)', () {
    testWidgets('a branch admin opens a school year as a draft', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        branchYears: [
          AcademicYear(
            academicYearId: 'y25',
            schoolId: 's1',
            branchId: 'north',
            name: '2025-26',
            startDate: DateTime(2025, 6, 1),
            endDate: DateTime(2026, 3, 31),
            status: AcademicYearStatus.active,
            schoolYearId: 'y25',
          ),
        ],
      );
      w.container.read(appRouterProvider).go(AppRoutes.settingsAcademicYears);
      await tester.pumpAndSettle();
      expect(find.text('School years (all branches)'), findsNothing);
      await tester.tap(find.text('Open a school year'));
      await tester.pumpAndSettle();
      // 2025-26 is already open here, 2019-20 is archived → only 2026-27
      expect(find.text('2026-27'), findsOneWidget);
      expect(find.text('2019-20'), findsNothing);
      await tester.tap(find.text('2026-27'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();
      expect(w.years.openCalls.single.yearId, 'y26');
      expect(w.years.openCalls.single.branches, ['north']);
    });

    testWidgets('a school admin gets a shortcut to the school-wide years', (
      tester,
    ) async {
      final w = await _pump(tester);
      w.container.read(appRouterProvider).go(AppRoutes.settingsAcademicYears);
      await tester.pumpAndSettle();
      await tester.tap(find.text('School years (all branches)'));
      await tester.pumpAndSettle();
      expect(find.text('Add school year'), findsOneWidget);
    });
  });
}
