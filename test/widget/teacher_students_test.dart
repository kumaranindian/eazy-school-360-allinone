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
import 'package:eazy_school_360/features/staff/domain/teacher_scope.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/teacher_scope_providers.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/staff_fakes.dart';
import '../support/student_fakes.dart';

const _uid = 'uid-t';

const _twoSections = TeacherScope([
  TeacherSection(academicYearId: 'y1', classId: 'c5', sectionId: 'sa'),
  TeacherSection(academicYearId: 'y1', classId: 'c6', sectionId: 'sb'),
]);

Future<({FakeStudentListRepository students, ProviderContainer container})>
_pump(
  WidgetTester tester, {
  required TeacherScope? scope,
  UserRole role = UserRole.teacher,
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
  final students = FakeStudentListRepository([
    fakeStudent(
      's1',
      first: 'Asha',
      last: 'Nair',
      admission: 'ADM-001',
      yearId: 'y1',
      classId: 'c5',
      sectionId: 'sa',
    ),
    fakeStudent(
      's2',
      first: 'Ravi',
      last: 'Menon',
      admission: 'ADM-002',
      yearId: 'y1',
      classId: 'c5',
      sectionId: 'sa',
    ),
    fakeStudent(
      's3',
      first: 'Meena',
      last: 'Pillai',
      admission: 'ADM-003',
      yearId: 'y1',
      classId: 'c6',
      sectionId: 'sb',
    ),
    fakeStudent(
      's4',
      first: 'Other',
      last: 'Class',
      admission: 'ADM-004',
      yearId: 'y1',
      classId: 'c9',
      sectionId: 'sz',
    ),
  ]);
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 't@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Teacher',
            email: 't@example.com',
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
              name: 'Rosewood',
              email: 'o@r.example',
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
      studentRepositoryProvider.overrideWithValue(students),
      teacherScopeRepositoryProvider.overrideWithValue(
        FakeTeacherScopeRepository(scope),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/students');
  await tester.pumpAndSettle();
  return (students: students, container: container);
}

void main() {
  testWidgets('a teacher sees only the students of an assigned section, '
      'asked for with year, class and section pinned', (tester) async {
    final w = await _pump(tester, scope: _twoSections);
    expect(find.text('Asha Nair'), findsOneWidget);
    expect(find.text('Ravi Menon'), findsOneWidget);
    expect(find.text('Meena Pillai'), findsNothing); // other assigned section
    expect(find.text('Other Class'), findsNothing); // not assigned at all
    expect(w.students.placementCalls, isNotEmpty);
    expect(
      w.students.placementCalls.every((c) => c.sectionId != null),
      isTrue,
      reason: 'a teacher query must name the section',
    );
    // never a branch-wide directory or count
    expect(w.students.fetchStatuses, isEmpty);
    expect(w.students.countCalls, isEmpty);
    expect(w.students.nameSearches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching class loads that section; search stays inside it', (
    tester,
  ) async {
    final w = await _pump(tester, scope: _twoSections);
    await tester.tap(find.byType(DropdownButtonFormField<TeacherSection>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c6 – sb').last);
    await tester.pumpAndSettle();
    expect(find.text('Meena Pillai'), findsOneWidget);
    expect(find.text('Asha Nair'), findsNothing);
    expect(w.students.placementCalls.last.classId, 'c6');
    expect(w.students.placementCalls.last.sectionId, 'sb');

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No student matches your search.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'mee');
    await tester.pumpAndSettle();
    expect(find.text('Meena Pillai'), findsOneWidget);
  });

  testWidgets('no teacherAccess yet: an actionable message and no student '
      'query is made', (tester) async {
    final w = await _pump(tester, scope: null);
    expect(find.textContaining("class access isn't set up"), findsOneWidget);
    expect(w.students.placementCalls, isEmpty);
    expect(find.text('Asha Nair'), findsNothing);
  });

  testWidgets('assigned to nothing: says so, queries nothing', (tester) async {
    final w = await _pump(tester, scope: TeacherScope.empty);
    expect(find.text('You have no class assigned yet.'), findsOneWidget);
    expect(w.students.placementCalls, isEmpty);
  });

  testWidgets('assignments without an academic year cannot be queried', (
    tester,
  ) async {
    final w = await _pump(
      tester,
      scope: const TeacherScope([
        TeacherSection(academicYearId: null, classId: 'c5', sectionId: 'sa'),
      ]),
    );
    expect(find.textContaining('missing an academic year'), findsOneWidget);
    expect(w.students.placementCalls, isEmpty);
  });

  testWidgets('an administrator still gets the branch directory', (
    tester,
  ) async {
    final w = await _pump(tester, scope: null, role: UserRole.branchAdmin);
    expect(w.students.fetchStatuses, isNotEmpty);
    expect(w.students.placementCalls, isEmpty);
  });

  testWidgets('a teacher has no Parents directory (route and navigation)', (
    tester,
  ) async {
    final w = await _pump(tester, scope: _twoSections);
    expect(find.text('Parents'), findsNothing);
    w.container.read(appRouterProvider).go('/parents');
    await tester.pumpAndSettle();
    expect(
      w.container.read(appRouterProvider).state.uri.path,
      isNot('/parents'),
    );
  });

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(820, 1180),
    Size(1440, 900),
  ]) {
    testWidgets('lays out at ${size.width.toInt()}x${size.height.toInt()} '
        'with larger text', (tester) async {
      await _pump(tester, scope: _twoSections, size: size, textScale: 1.5);
      expect(find.text('Asha Nair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
