import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject_type.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
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

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/school_year_fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High School of Excellence and Learning',
  email: 'office@rosewood.example',
  phone: '+91 98765 43210',
  addressLine1: '12 Long Academic Boulevard',
  city: 'Chennai',
  status: SchoolStatus.active,
);

final _years = [
  AcademicYear(
    academicYearId: 'y26',
    schoolId: 'school-1',
    branchId: 'main',
    name: 'Academic Year 2026-2027 (Primary Campus)',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2027, 3, 31),
    status: AcademicYearStatus.active,
  ),
];

final _classes = [
  for (var i = 1; i <= 3; i++)
    SchoolClass(
      classId: 'c$i',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      name: 'Class $i — Foundation Stage',
      code: 'C$i',
      displayOrder: i,
      status: i == 3 ? ActivationStatus.inactive : ActivationStatus.active,
    ),
];

final _sections = [
  for (final n in ['A', 'B'])
    Section(
      sectionId: 's$n',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      classId: 'c1',
      name: 'Section $n',
      capacity: 40,
      status: ActivationStatus.active,
    ),
];

final _subjects = [
  Subject(
    subjectId: 'sub1',
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: 'y26',
    name: 'Mathematics and Applied Reasoning',
    code: 'MATH',
    type: SubjectType.core,
    displayOrder: 1,
    status: ActivationStatus.active,
  ),
];

Future<ProviderContainer> _pump(
  WidgetTester tester,
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
          _uid: const UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: UserRole.schoolAdmin,
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
              code: 'MAIN',
              city: 'Chennai',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(
          years: _years,
          classes: _classes,
          sections: _sections,
          subjects: _subjects,
        ),
      ),
      calendarRepositoryProvider.overrideWithValue(FakeCalendarRepository()),
      schoolYearRepositoryProvider.overrideWithValue(
        FakeSchoolYearRepository(),
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

const _pages = <(String, String, String)>[
  (AppRoutes.settingsBranches, 'Branches', 'Add branch'),
  (AppRoutes.settingsAcademicYears, 'Academic years', 'Open a school year'),
  (AppRoutes.settingsClasses, 'Classes', 'Add class'),
  (AppRoutes.settingsSections, 'Sections', 'Add section'),
  (AppRoutes.settingsSubjects, 'Subjects', 'Add subject'),
  (AppRoutes.settingsHolidays, 'Holiday calendar', 'Add holiday'),
  (AppRoutes.settingsWorkingDays, 'Working days', ''),
];

void main() {
  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('phone', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'settings pages lay out without overflow: $name, text x$scale',
        (tester) async {
          final container = await _pump(tester, size, scale);
          final router = container.read(appRouterProvider);
          for (final (route, title, action) in _pages) {
            router.go(route);
            await tester.pumpAndSettle();
            expect(find.text(title), findsWidgets, reason: '$route title');
            if (action.isNotEmpty) {
              expect(
                find.text(action),
                findsOneWidget,
                reason: '$route action',
              );
            }
            expect(
              find.byTooltip('Back to Settings'),
              findsOneWidget,
              reason: '$route back',
            );
            expect(tester.takeException(), isNull, reason: route);
          }
          router.go(AppRoutes.school);
          await tester.pumpAndSettle();
          expect(find.text('Email'), findsOneWidget);
          expect(find.text('Edit'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'school profile');
        },
      );
    }
  }

  testWidgets('the back button returns to the Settings hub', (tester) async {
    final container = await _pump(tester, const Size(390, 844), 1.0);
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.settingsClasses);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Settings'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.settings,
    );
  });

  testWidgets('class actions are one menu, not four icon buttons', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844), 1.0).then((c) async {
      c.read(appRouterProvider).go(AppRoutes.settingsClasses);
      await tester.pumpAndSettle();
    });
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    await tester.tap(find.byTooltip('Actions for Class 1 — Foundation Stage'));
    await tester.pumpAndSettle();
    for (final label in ['Edit', 'Manage subjects', 'Move up', 'Move down']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
