import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_registers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance_repository.dart';
import 'package:eazy_school_360/features/attendance/presentation/providers/attendance_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/fees/presentation/providers/fee_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart' as att;
import '../support/fakes.dart';
import '../support/fee_fakes.dart';

const _uid = 'uid-p';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

class _FakeParents implements ParentRepository {
  final List<Student> children;
  _FakeParents(this.children);

  @override
  Future<List<Student>> getChildrenForParent({
    required String schoolId,
    required String parentId,
    String? branchId,
  }) async => children;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serves canned attendance per student; everything else is unsupported.
class _FakeAttendance implements StudentAttendanceRepository {
  final Map<String, List<StudentAttendance>> byStudent;
  final List<String> askedFor = [];
  _FakeAttendance(this.byStudent);

  @override
  Future<AttendanceRange<StudentAttendance>> fetchStudentRange({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String fromKey,
    required String toKey,
  }) async {
    askedFor.add(studentId);
    return AttendanceRange(
      (byStudent[studentId] ?? const [])
          .where(
            (r) =>
                r.dateKey.compareTo(fromKey) >= 0 &&
                r.dateKey.compareTo(toKey) <= 0,
          )
          .toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StudentAttendance _rec(String studentId, DateTime day, AttendanceStatus s) {
  final key =
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  return StudentAttendance(
    attendanceId: '${key}_$studentId',
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: 'y1',
    dateKey: key,
    studentId: studentId,
    academicRecordId: 'r1',
    classId: 'c5',
    sectionId: 'sa',
    status: s,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Student> children,
  required _FakeAttendance attendance,
  String? linkedParentId = 'parent-1',
  UserRole role = UserRole.parent,
  Size size = const Size(1000, 1200),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'p@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Priya Parent',
            email: 'p@example.com',
            role: role,
            status: UserStatus.active,
            linkedParentId: linkedParentId,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
      parentRepositoryProvider.overrideWithValue(_FakeParents(children)),
      studentAttendanceRepositoryProvider.overrideWithValue(attendance),
      invoiceRepositoryProvider.overrideWithValue(
        FakeInvoiceRepository(
          invoices: [
            fakeInvoice(studentId: 'stu-1', payable: 100000, paid: 40000),
          ],
        ),
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

Student _child(String id, String first) =>
    att.fakeStudent(id, first, academicYearId: 'y1');

void main() {
  final today = DateTime.now();
  final first = DateTime(today.year, today.month, 1);

  testWidgets(
    'parent home shows the child, this month\'s attendance % and the fee balance',
    (tester) async {
      await _pump(
        tester,
        children: [_child('stu-1', 'Asha')],
        attendance: _FakeAttendance({
          'stu-1': [
            _rec('stu-1', first, AttendanceStatus.present),
            _rec(
              'stu-1',
              DateTime(first.year, first.month, 1),
              AttendanceStatus.present,
            ),
          ],
        }),
      );
      expect(find.text('Asha Kumar'), findsOneWidget);
      expect(find.text('Attendance this month'), findsOneWidget);
      expect(find.text('100% present'), findsOneWidget);
      expect(find.text('Fees due'), findsOneWidget);
      expect(find.textContaining('600'), findsWidgets); // balance 60,000 minor
      // One child: no switcher chips.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('with two children the switcher changes what is shown', (
    tester,
  ) async {
    final repo = _FakeAttendance({
      'stu-1': [_rec('stu-1', first, AttendanceStatus.present)],
      'stu-2': [_rec('stu-2', first, AttendanceStatus.absent)],
    });
    await _pump(
      tester,
      children: [_child('stu-1', 'Asha'), _child('stu-2', 'Ravi')],
      attendance: repo,
    );
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('100% present'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ravi'));
    await tester.pumpAndSettle();
    expect(find.text('0% present'), findsOneWidget);
    expect(repo.askedFor, containsAll(['stu-1', 'stu-2']));
  });

  testWidgets('/my-attendance shows the calendar and the tally for the child', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      children: [_child('stu-1', 'Asha')],
      attendance: _FakeAttendance({
        'stu-1': [
          _rec('stu-1', first, AttendanceStatus.present),
          _rec(
            'stu-1',
            DateTime(first.year, first.month, 2),
            AttendanceStatus.absent,
          ),
        ],
      }),
    );
    container.read(appRouterProvider).go(AppRoutes.myAttendance);
    await tester.pumpAndSettle();
    expect(find.text('Asha Kumar'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    // Cannot page past the current month.
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);
    // Previous month has no records.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(
      find.text('No attendance has been recorded for this month.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unlinked parent gets an explanation, not an error', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      linkedParentId: null,
      children: const [],
      attendance: _FakeAttendance({}),
    );
    expect(find.textContaining("isn't linked"), findsOneWidget);
    container.read(appRouterProvider).go(AppRoutes.myAttendance);
    await tester.pumpAndSettle();
    expect(find.textContaining("isn't linked"), findsOneWidget);
  });

  testWidgets('staff cannot open /my-attendance', (tester) async {
    final container = await _pump(
      tester,
      role: UserRole.teacher,
      linkedParentId: null,
      children: const [],
      attendance: _FakeAttendance({}),
    );
    container.read(appRouterProvider).go(AppRoutes.myAttendance);
    await tester.pumpAndSettle();
    final location = container
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();
    expect(location, isNot(AppRoutes.myAttendance));
  });

  for (final size in [const Size(360, 800), const Size(1400, 900)]) {
    testWidgets('no overflow at ${size.width.toInt()}px (home and calendar)', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        size: size,
        children: [_child('stu-1', 'Asha'), _child('stu-2', 'Ravi')],
        attendance: _FakeAttendance({
          'stu-1': [_rec('stu-1', first, AttendanceStatus.late)],
        }),
      );
      expect(tester.takeException(), isNull);
      container.read(appRouterProvider).go(AppRoutes.myAttendance);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
