import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/directory_list.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/staff_hero.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/staff_toolbar.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_access_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/login_access_fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _longSchool =
    'Rosewood International High School of Excellence and Learning, Chennai';

final _academic = FakeAcademicStructureRepository(
  years: [
    AcademicYear(
      academicYearId: 'y26',
      schoolId: 'school-1',
      branchId: 'main',
      name: '2026-27',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 3, 31),
      status: AcademicYearStatus.active,
    ),
  ],
  classes: [
    const SchoolClass(
      classId: 'c1',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      name: 'Class 1',
      displayOrder: 1,
      status: ActivationStatus.active,
    ),
  ],
  sections: [
    const Section(
      sectionId: 'sA',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      classId: 'c1',
      name: 'A',
      status: ActivationStatus.active,
    ),
  ],
);

List<Staff> _people() => [
  fakeStaff('t1', first: 'Meera', last: 'Iyer', code: 'T-1', isTeacher: true),
  fakeStaff('t2', first: 'Arun', last: 'Kumar', code: 'T-2', isTeacher: true),
  for (var i = 3; i <= 6; i++)
    fakeStaff('s$i', first: 'Office', last: 'Person$i', code: 'S-$i'),
  fakeStaff(
    's8',
    first: 'Venkatasubramanian',
    last: 'Ramachandran Iyer-Thiruvengadam',
    code: 'EMP-LONG-IDENTIFIER-0008',
  ),
];

LoginAccess _access() => LoginAccess(
  id: 't1',
  uid: 'uid-t1',
  kind: LoginKind.staff,
  name: 'Meera Iyer',
  userType: 'TEACHER',
  registeredEmail: 'meera@example.org',
  registeredPhone: '+919876543210',
  schoolMethods: LoginMethod.values,
  hasAccount: true,
  enabled: true,
  methods: const [LoginMethod.password],
  effective: const [LoginMethod.password],
  activation: LoginActivation.active,
  emailVerified: true,
  phoneVerified: false,
  lastLogin: DateTime(2026, 5, 3, 9, 30),
  legacy: false,
  manageable: true,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String route = '/staff',
  Size size = const Size(1440, 900),
  double textScale = 1.0,
  UserRole role = UserRole.branchAdmin,
  FakeStaffRepository? repo,
  String schoolName = 'Rosewood High',
  Map<String, Branch>? branches,
  List<Staff>? people,
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
          schools: {
            'school-1': School(
              schoolId: 'school-1',
              name: schoolName,
              email: 'office@rosewood.example',
              status: SchoolStatus.active,
            ),
          },
          branches:
              branches ??
              {
                'school-1/main': const Branch(
                  branchId: 'main',
                  schoolId: 'school-1',
                  name: 'Main',
                  status: BranchStatus.active,
                ),
              },
        ),
      ),
      staffRepositoryProvider.overrideWithValue(
        repo ?? FakeStaffRepository(staff: people ?? _people()),
      ),
      staffSetupRepositoryProvider.overrideWithValue(
        FakeStaffSetupRepository(),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(
        FakeTeacherAssignmentRepository(),
      ),
      academicStructureRepositoryProvider.overrideWithValue(_academic),
      loginAccessRepositoryProvider.overrideWithValue(
        FakeLoginAccessRepository(access: _access()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(route);
  await tester.pumpAndSettle();
  return container;
}

const _widths = <double>[360, 390, 768, 1024, 1280, 1440, 1920];

void main() {
  group('staff: every required width', () {
    for (final width in _widths) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('${width.toInt()}px, text x$scale: no overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            size: Size(width, width < 600 ? 800 : 900),
            textScale: scale,
            schoolName: _longSchool,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Staff directory'), findsOneWidget);
          expect(find.text('Meera Iyer'), findsOneWidget);
          final card = tester.getRect(find.byType(DirectoryListCard));
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(width));
        });
      }
    }
  });

  group('staff: structure', () {
    for (final width in [360.0, 390.0]) {
      testWidgets(
        '${width.toInt()}: cards, a stacked toolbar, filters in a sheet',
        (tester) async {
          await _pump(tester, size: Size(width, 800));
          expect(find.byType(DirectoryCard), findsWidgets);
          expect(find.byType(DirectoryTable), findsNothing);
          expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
          expect(find.text('Filters · 1'), findsOneWidget);
          expect(find.text('—'), findsNothing); // never on a phone
          await tester.tap(find.text('Filters · 1'));
          await tester.pumpAndSettle();
          for (final label in [
            'Status',
            'Department',
            'Designation',
            'Employment type',
          ]) {
            expect(find.text(label), findsWidgets, reason: label);
          }
        },
      );
    }

    testWidgets('768: a table with the key columns and an inline toolbar', (
      tester,
    ) async {
      await _pump(tester, size: const Size(768, 900));
      expect(find.byType(DirectoryTable), findsOneWidget);
      for (final header in ['STAFF', 'ID', 'DEPARTMENT', 'STATUS']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('PHONE'), findsNothing); // dropped by width
      expect(find.byTooltip('Search by'), findsOneWidget);
    });

    testWidgets('1440: every column, and at least six rows visible', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      for (final header in [
        'STAFF',
        'ID',
        'DEPARTMENT',
        'DESIGNATION',
        'LOGIN',
        'PHONE',
        'STATUS',
      ]) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      for (final name in [
        'Meera Iyer',
        'Arun Kumar',
        'Office Person3',
        'Office Person4',
        'Office Person5',
        'Office Person6',
      ]) {
        expect(tester.getRect(find.text(name)).bottom, lessThan(900));
      }
    });

    testWidgets('rows are about 46 tall', (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      final r1 = tester.getRect(find.text('Meera Iyer'));
      final r2 = tester.getRect(find.text('Arun Kumar'));
      expect((r2.center.dy - r1.center.dy).abs(), inInclusiveRange(46, 48));
    });

    testWidgets('the footer counts the plain list and pages as before', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      expect(find.textContaining('Showing 7'), findsOneWidget);
      expect(find.text('Load more'), findsNothing); // nothing further
    });
  });

  group('staff: kept behaviour', () {
    testWidgets('search-by menu, and filters pause while searching', (
      tester,
    ) async {
      final repo = FakeStaffRepository(staff: _people());
      await _pump(tester, size: const Size(1440, 900), repo: repo);
      expect(find.byTooltip('Search by'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Status: Active'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Meera');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.searchCalls.single['query'], 'Meera');
      expect(
        find.textContaining('Filters are paused while searching'),
        findsOneWidget,
      );
      expect(find.widgetWithText(InputChip, 'Status: Active'), findsNothing);
      expect(find.text('Arun Kumar'), findsNothing);
    });

    testWidgets('selecting people to give logins to shows checkboxes', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give login access'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting works on a phone card too', (tester) async {
      await _pump(tester, size: const Size(390, 800));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give login access'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add staff is still the primary action', (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      expect(find.text('Add staff'), findsOneWidget);
    });

    testWidgets('a school admin chooses the branch from the hero', (
      tester,
    ) async {
      final c = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        branches: {
          'school-1/main': const Branch(
            branchId: 'main',
            schoolId: 'school-1',
            name: 'Main',
            status: BranchStatus.active,
          ),
          'school-1/south': const Branch(
            branchId: 'south',
            schoolId: 'school-1',
            name: 'South Campus',
            status: BranchStatus.active,
          ),
        },
      );
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Branch'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Choose branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('South Campus').last);
      await tester.pumpAndSettle();
      expect(c.read(selectedStaffBranchIdProvider), 'south');
    });
  });

  group('the key icon (Login access)', () {
    for (final route in ['/staff', '/teachers']) {
      testWidgets('$route: every row has it for someone who manages staff', (
        tester,
      ) async {
        await _pump(tester, route: route);
        final rows =
            find.byType(DirectoryCard).evaluate().length +
            tester.widgetList(find.byKey(const ValueKey('t1'))).length;
        expect(rows, greaterThan(0));
        expect(find.byTooltip('Login access'), findsWidgets);
        expect(
          find.byTooltip('Login access').evaluate().length,
          tester.widgetList(find.byType(PersonAvatar)).length,
          reason: 'one key per row',
        );
      });

      testWidgets('$route: a phone card has it too', (tester) async {
        await _pump(tester, route: route, size: const Size(390, 800));
        expect(find.byTooltip('Login access'), findsWidgets);
        final key = tester.getRect(find.byTooltip('Login access').first);
        expect(key.height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping it opens that person\'s Login access', (tester) async {
      await _pump(tester, route: '/teachers');
      await tester.tap(find.byTooltip('Login access').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Meera Iyer'), findsWidgets);
      expect(find.textContaining('Login access'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone who can view but not manage staff does not see it', (
      tester,
    ) async {
      await _pump(tester, route: '/teachers', role: UserRole.finance);
      expect(find.text('Meera Iyer'), findsOneWidget);
      expect(find.byTooltip('Login access'), findsNothing);
    });

    testWidgets('it does not make rows taller than 46', (tester) async {
      await _pump(tester, route: '/teachers');
      final r1 = tester.getRect(find.text('Meera Iyer'));
      final r2 = tester.getRect(find.text('Arun Kumar'));
      expect((r2.center.dy - r1.center.dy).abs(), inInclusiveRange(46, 48));
    });
  });

  group('staff and teachers share one layout', () {
    testWidgets('the same header, toolbar and list card, in the same places', (
      tester,
    ) async {
      Future<Map<String, Rect>> measure(String route) async {
        await _pump(tester, route: route);
        final out = {
          'hero': tester.getRect(find.byType(StaffHero)),
          'toolbar': tester.getRect(find.byType(StaffToolbar)),
          'list': tester.getRect(find.byType(DirectoryListCard)),
        };
        // a new app for the next route
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        return out;
      }

      final staff = await measure('/staff');
      final teachers = await measure('/teachers');
      for (final k in ['hero', 'toolbar', 'list']) {
        expect(staff[k]!.left, teachers[k]!.left, reason: '$k left');
        expect(staff[k]!.width, teachers[k]!.width, reason: '$k width');
      }
      expect(staff['hero']!.height, teachers['hero']!.height);
      expect(staff['hero']!.top, teachers['hero']!.top);
    });
  });

  testWidgets('staff status: a status the counts do not cover shows no total', (
    tester,
  ) async {
    final repo = FakeStaffRepository(
      staff: [
        fakeStaff(
          'r1',
          first: 'Rita',
          last: 'Retired',
          code: 'R-1',
          status: StaffStatus.retired,
        ),
      ],
    );
    await _pump(tester, repo: repo);
    // default filter is Active, so a retired person is not listed
    expect(find.text('Rita Retired'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
