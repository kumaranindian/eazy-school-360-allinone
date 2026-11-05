import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/app_version.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/dashboard/domain/dashboard_summaries.dart';
import 'package:eazy_school_360/features/dashboard/presentation/providers/admin_dashboard_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
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

final _year = AcademicYear(
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime.utc(2026, 6, 1),
  endDate: DateTime.utc(2027, 3, 31),
  status: AcademicYearStatus.active,
);

const _attendance = AttendanceToday(
  expected: 120,
  present: 90,
  absent: 10,
  marked: 100,
  registersTaken: 4,
);
const _fees = FeeMonthCard(
  collectedThisMonthMinor: 12500000,
  outstandingMinor: 4000000,
  collectionRatePercent: 75,
  invoiceCount: 40,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  UserRole role,
  Size size, {
  double textScale = 1.0,
  AttendanceToday? attendance = _attendance,
  FeeMonthCard? fees = _fees,
  Future<AttendanceToday?> Function()? attendanceLoader,
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
      dashboardStudentCountProvider.overrideWith((ref, key) async => 120),
      dashboardParentCountProvider.overrideWith((ref, key) async => 87),
      staffCountsProvider.overrideWith(
        (ref, key) async => (total: 15, active: 14, onNotice: 1, inactive: 0),
      ),
      dashboardYearProvider.overrideWith((ref, key) async => _year),
      attendanceTodayProvider.overrideWith(
        (ref, key) => attendanceLoader != null
            ? attendanceLoader()
            : Future.value(attendance),
      ),
      feeMonthCardProvider.overrideWith((ref, key) async => fees),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return container;
}

const _phone = Size(390, 844);
const _phoneLandscape = Size(844, 390);
const _tablet = Size(820, 1180);
const _desktop = Size(1440, 900);

void main() {
  testWidgets('the school admin lands on the dashboard and sees every block', (
    tester,
  ) async {
    final c = await _pump(tester, UserRole.schoolAdmin, _phone);
    expect(
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
      '/dashboard',
    );
    for (final t in [
      'Quick Overview',
      'Students',
      'Parents',
      'Staff',
      "Today's Attendance",
      'Fee Collection',
    ]) {
      expect(find.text(t, skipOffstage: false), findsWidgets, reason: t);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('real numbers, not placeholders', (tester) async {
    await _pump(tester, UserRole.schoolAdmin, _desktop);
    expect(find.text('120'), findsWidgets); // students + total students
    expect(find.text('87'), findsOneWidget); // parents: a count, never "View"
    expect(find.text('14'), findsOneWidget); // active staff
    expect(find.text('View'), findsNothing);
    // attendance: present 90, absent 10, not marked 20, completion 83% (100/120)
    expect(find.text('90'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    // fees: the school's currency, exact amounts
    expect(find.textContaining('₹1,25,000.00'), findsWidgets);
    expect(find.textContaining('₹40,000.00'), findsWidgets);
    expect(find.text('75%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all eight quick actions, comfortable touch targets', (
    tester,
  ) async {
    await _pump(tester, UserRole.schoolAdmin, _phone);
    const labels = [
      'Add Student',
      'Mark Attendance',
      'Create Announcement',
      'Collect Fees',
      'Add Staff',
      'Timetable',
      'Homework',
      'Reports',
    ];
    await tester.scrollUntilVisible(
      find.text('Quick Actions'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (final l in labels) {
      final f = find.text(l);
      await tester.scrollUntilVisible(
        f.first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(f, findsWidgets, reason: l);
    }
    final tile = find.ancestor(
      of: find.text('Add Student').last,
      matching: find.byType(InkWell),
    );
    final size = tester.getSize(tile.first);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('quick action navigates to the existing screen', (tester) async {
    final c = await _pump(tester, UserRole.schoolAdmin, _desktop);
    await tester.tap(find.text('Add Student').last);
    await tester.pumpAndSettle();
    expect(
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
      '/students/new',
    );
  });

  testWidgets('insights banner opens the existing reports screen', (
    tester,
  ) async {
    final c = await _pump(tester, UserRole.schoolAdmin, _desktop);
    await tester.tap(find.text('School Insights'));
    await tester.pumpAndSettle();
    expect(
      c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
      '/attendance/reports',
    );
  });

  testWidgets('footer: powered by, and the version from config', (
    tester,
  ) async {
    await _pump(tester, UserRole.schoolAdmin, _desktop);
    await tester.scrollUntilVisible(
      find.text('Powered by EazySchool 360').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(appVersionLabel), findsWidgets);
  });

  testWidgets('no attendance recorded: an empty state with Mark Attendance', (
    tester,
  ) async {
    await _pump(tester, UserRole.schoolAdmin, _phone, attendance: null);
    await tester.scrollUntilVisible(
      find.text('Mark Attendance').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('has not been recorded today'), findsNothing);
    // expected = 0 when the provider returns null -> "No students to mark yet."
    expect(find.text('No students to mark yet.'), findsOneWidget);
  });

  testWidgets('unmarked students are not shown as absent', (tester) async {
    await _pump(
      tester,
      UserRole.schoolAdmin,
      _desktop,
      attendance: const AttendanceToday(
        expected: 50,
        present: 0,
        absent: 0,
        marked: 0,
        registersTaken: 0,
      ),
    );
    expect(
      find.textContaining('has not been recorded today for 50 students'),
      findsOneWidget,
    );
    expect(find.text('Absent'), findsNothing);
  });

  testWidgets('an attendance error shows a retry, the rest still renders', (
    tester,
  ) async {
    await _pump(
      tester,
      UserRole.schoolAdmin,
      _desktop,
      attendanceLoader: () => Future.error(StateError('boom')),
    );
    expect(
      find.text("Today's attendance could not be loaded."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Fee Collection'), findsOneWidget);
  });

  testWidgets('a loading attendance card shows progress, not a number', (
    tester,
  ) async {
    tester.view.physicalSize = _desktop;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Never completes.
    final c = await _pumpNoSettle(tester, () => Future.any(const []));
    expect(c, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  for (final (name, size) in [
    ('phone portrait', _phone),
    ('phone landscape', _phoneLandscape),
    ('tablet', _tablet),
    ('desktop', _desktop),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('lays out without overflow: $name, text x$scale', (
        tester,
      ) async {
        await _pump(tester, UserRole.schoolAdmin, size, textScale: scale);
        expect(tester.takeException(), isNull);
        // scroll the whole page: overflow shows up as a recorded exception
        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final role in [UserRole.teacher, UserRole.finance, UserRole.parent]) {
    testWidgets('${role.name} keeps their own dashboard (no admin cards)', (
      tester,
    ) async {
      await _pump(tester, role, _desktop);
      expect(find.text('Fee Collection'), findsNothing);
      expect(find.text("Today's Attendance"), findsNothing);
    });
  }

  testWidgets(
    'dark mode keeps working (no forced light surface, no overflow)',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pump(tester, UserRole.schoolAdmin, _phone);
      expect(find.text('Fee Collection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a branch admin keeps the existing staff home', (tester) async {
    await _pump(tester, UserRole.branchAdmin, _desktop);
    expect(find.text('Fee Collection'), findsNothing);
    expect(find.text('Quick Overview'), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpNoSettle(
  WidgetTester tester,
  Future<AttendanceToday?> Function() loader,
) async {
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
            name: 'Grace',
            email: 'grace@example.com',
            role: UserRole.schoolAdmin,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
      dashboardStudentCountProvider.overrideWith((ref, key) async => 120),
      dashboardParentCountProvider.overrideWith((ref, key) async => 87),
      dashboardYearProvider.overrideWith((ref, key) async => _year),
      attendanceTodayProvider.overrideWith((ref, key) => loader()),
      feeMonthCardProvider.overrideWith((ref, key) async => _fees),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  return container;
}
