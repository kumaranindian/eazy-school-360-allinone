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
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';

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

Future<(ProviderContainer, FakeStaffRepository)> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final staff = FakeStaffRepository(
    staff: [
      fakeStaff(
        't1',
        first: 'Meera',
        last: 'Iyer',
        code: 'T-1',
        isTeacher: true,
      ),
      fakeStaff(
        't2',
        first: 'Arun',
        last: 'Kumar',
        code: 'T-2',
        isTeacher: true,
        status: StaffStatus.onNotice,
      ),
    ],
  );
  final assignments = FakeTeacherAssignmentRepository()
    ..existing = [
      TeacherAssignment(
        assignmentId: 'a1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'y26',
        teacherStaffId: 't1',
        classId: 'c1',
        sectionId: 'sA',
        isClassTeacher: true,
        startDate: DateTime(2026, 6, 1),
        status: TeacherAssignmentStatus.active,
      ),
    ];
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
      staffRepositoryProvider.overrideWithValue(staff),
      staffSetupRepositoryProvider.overrideWithValue(
        FakeStaffSetupRepository(),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(assignments),
      academicStructureRepositoryProvider.overrideWithValue(_academic),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/teachers');
  await tester.pumpAndSettle();
  return (container, staff);
}

void main() {
  testWidgets('phone: search, one Filters button and headcount chips', (
    tester,
  ) async {
    final (_, repo) = await _pump(tester);

    expect(find.text('Meera Iyer'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Filters · 1'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Status: Active'), findsOneWidget);
    expect(repo.countCalls, isNotEmpty);
    expect(find.bySemanticsLabel('All: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'choosing a class takes over from search and status and says so',
    (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Filters · 1'));
      await tester.pumpAndSettle();
      // The year is context, not a filter; the rest are filters.
      expect(find.text('Academic year'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String?>, 'All classes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Showing teachers with active assignments'),
        findsOneWidget,
      );
      expect(find.widgetWithText(InputChip, 'Class: Class 1'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Meera Iyer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('import and export live in the ⋮ menu', (tester) async {
    await _pump(tester);
    expect(find.text('Export (CSV)'), findsNothing);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Import (CSV)'), findsOneWidget);
    expect(find.text('Export (CSV)'), findsOneWidget);
  });

  testWidgets('lays out on tablet and desktop without overflow', (
    tester,
  ) async {
    await _pump(tester, size: const Size(900, 1000));
    expect(find.text('Meera Iyer'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
