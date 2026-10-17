import 'dart:async';

import 'package:eazy_school_360/features/staff/domain/teacher_scope.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/teacher_scope_providers.dart';
import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings_repository.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_settings_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_balance.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_repositories.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:eazy_school_360/features/leave/presentation/providers/leave_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
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

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/leave_fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';

final _year = AcademicYear(
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime(DateTime.now().year - 1, 1, 1),
  endDate: DateTime(DateTime.now().year + 1, 12, 31),
  status: AcademicYearStatus.active,
);

class _FakeSettings implements AcademicSettingsRepository {
  @override
  Future<AcademicSettings> getSettings(
    String schoolId,
    String branchId,
  ) async => AcademicSettings(schoolId: schoolId, branchId: branchId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeParentRepository implements ParentRepository {
  final List<Student> children;

  _FakeParentRepository(this.children);

  @override
  Future<List<Student>> getChildrenForParent({
    required String schoolId,
    required String parentId,
    String? branchId,
  }) async => children;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _pad(int n) => n.toString().padLeft(2, '0');
String _key(int day) {
  final n = DateTime.now();
  return '${n.year}-${_pad(n.month)}-${_pad(day)}';
}

LeaveType _type({
  LeaveKind kind = LeaveKind.student,
  String code = 'SICK',
  String name = 'Sick leave',
  LeavePayType pay = LeavePayType.notApplicable,
  bool doc = false,
  int? entitlement,
  ExceedPolicy exceed = ExceedPolicy.block,
}) => LeaveType(
  typeId: LeaveType.idFor(kind, code),
  schoolId: 'school-1',
  branchId: 'main',
  kind: kind,
  code: code,
  name: name,
  payType: pay,
  requiresDocument: doc,
  annualEntitlementUnits: entitlement,
  exceedPolicy: exceed,
);

class _World {
  final ProviderContainer container;
  final FakeLeaveApplicationRepository apps;
  final FakeLeaveTypeRepository types;
  final FakeLeaveBalanceRepository balances;
  final FakeLeaveCalendarRepository calendar;
  final FakeLeaveNotificationRepository notices;

  _World(
    this.container,
    this.apps,
    this.types,
    this.balances,
    this.calendar,
    this.notices,
  );

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();

  Future<void> go(WidgetTester tester, String path) async {
    container.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
  }
}

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  FakeLeaveApplicationRepository? apps,
  FakeLeaveTypeRepository? types,
  FakeLeaveBalanceRepository? balances,
  FakeLeaveCalendarRepository? calendar,
  FakeCalendarRepository? schoolCalendar,
  FakeLeaveNotificationRepository? notices,
  List<Student> children = const [],
  String? linkedParentId,
  bool staffRecord = false,
  Size size = const Size(1400, 1000),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final a = apps ?? FakeLeaveApplicationRepository();
  final t =
      types ??
      FakeLeaveTypeRepository(
        types: [
          _type(),
          _type(code: 'MEDICAL', name: 'Medical', doc: true),
          _type(
            kind: LeaveKind.staff,
            code: 'CL',
            name: 'Casual leave',
            pay: LeavePayType.paid,
            entitlement: 24,
          ),
        ],
      );
  final b = balances ?? FakeLeaveBalanceRepository();
  final c = calendar ?? FakeLeaveCalendarRepository();
  final n = notices ?? FakeLeaveNotificationRepository();

  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'u@example.com'),
        ),
      ),
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
            linkedParentId: linkedParentId,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
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
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(
          years: [_year],
          classes: [
            const SchoolClass(
              classId: 'c5',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              name: 'Class 5',
              displayOrder: 1,
              status: ActivationStatus.active,
            ),
          ],
          sections: [
            const Section(
              sectionId: 'sa',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              classId: 'c5',
              name: 'A',
              status: ActivationStatus.active,
            ),
          ],
        ),
      ),
      teacherScopeRepositoryProvider.overrideWithValue(
        FakeTeacherScopeRepository(
          const TeacherScope([
            TeacherSection(
              academicYearId: 'y1',
              classId: 'c5',
              sectionId: 'sa',
            ),
          ]),
        ),
      ),
      academicSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      calendarRepositoryProvider.overrideWithValue(
        schoolCalendar ?? FakeCalendarRepository(),
      ),
      parentRepositoryProvider.overrideWithValue(
        _FakeParentRepository(children),
      ),
      staffRepositoryProvider.overrideWithValue(
        FakeStaffRepository(
          staff: [
            if (staffRecord)
              fakeStaff('s9', first: 'Priya', last: 'Iyer', userId: _uid),
          ],
        ),
      ),
      leaveApplicationRepositoryProvider.overrideWithValue(a),
      leaveTypeRepositoryProvider.overrideWithValue(t),
      leaveBalanceRepositoryProvider.overrideWithValue(b),
      leaveCalendarRepositoryProvider.overrideWithValue(c),
      leaveNotificationRepositoryProvider.overrideWithValue(n),
      leaveReportRepositoryProvider.overrideWithValue(
        FakeLeaveReportRepository(),
      ),
      leaveAttachmentStoreProvider.overrideWithValue(
        FakeLeaveAttachmentStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, a, t, b, c, n);
}

Finder _filled(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;

Future<void> _pickDay(WidgetTester tester, String button, int day) async {
  // Once a first day is chosen the "Last day" button reads "To dd/mm/yyyy".
  final finder = button == 'Last day'
      ? find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == 'Last day' || (w.data ?? '').startsWith('To ')),
        )
      : find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == 'First day' || (w.data ?? '').startsWith('From ')),
        );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text('$day').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _chooseType(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> _fillStudentForm(
  WidgetTester tester, {
  String type = 'Sick leave',
  String reason = 'Fever and rest',
}) async {
  await _chooseType(tester, type);
  await _pickDay(tester, 'First day', 15);
  await _pickDay(tester, 'Last day', 16);
  await tester.enterText(find.widgetWithText(TextField, 'Reason'), reason);
  await tester.pumpAndSettle();
}

void main() {
  final child = fakeStudent('stu-1', 'Anil', academicYearId: 'y1');

  group('route and navigation permissions', () {
    testWidgets('a parent reaches only /my-leave', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child],
      );
      await w.go(tester, '/my-leave');
      expect(w.location, '/my-leave');
      for (final p in [
        '/leave',
        '/leave/applications',
        '/leave/applications/lv-1',
        '/leave/apply',
        '/leave/types',
        '/leave/balances',
        '/leave/calendar',
        '/leave/reports',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets(
      'a teacher has self-service and the calendar, nothing administrative',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          staffRecord: true,
        );
        await w.go(tester, '/my-leave');
        expect(w.location, '/my-leave');
        await w.go(tester, '/leave/calendar');
        expect(w.location, '/leave/calendar');
        for (final p in [
          '/leave',
          '/leave/applications',
          '/leave/types',
          '/leave/balances',
          '/leave/reports',
          '/leave/apply',
        ]) {
          await w.go(tester, p);
          expect(w.location, '/dashboard', reason: p);
        }
      },
    );

    testWidgets('finance has self-service only', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      await w.go(tester, '/my-leave');
      expect(w.location, '/my-leave');
      for (final p in ['/leave', '/leave/calendar', '/leave/applications']) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets('a branch admin opens every leave screen', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      for (final p in [
        '/leave',
        '/leave/applications',
        '/leave/apply',
        '/leave/types',
        '/leave/balances',
        '/leave/calendar',
        '/leave/reports',
        '/my-leave',
      ]) {
        await w.go(tester, p);
        expect(w.location, p);
      }
    });

    testWidgets(
      'on a phone Leave sits under "More" with the other destinations',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.schoolAdmin,
          size: const Size(390, 844),
        );
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        // The dashboard also has a "Leave" quick link; scope to the sheet.
        final inSheet = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Leave'),
        );
        expect(inSheet, findsOneWidget);
        expect(find.text('My Leave'), findsOneWidget);
        await tester.tap(inSheet);
        await tester.pumpAndSettle();
        expect(w.location, '/leave');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('dashboard', () {
    testWidgets('shows what is waiting, from the aggregate counts', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        apps: FakeLeaveApplicationRepository(pending: 5),
      );
      await w.go(tester, '/leave');
      expect(find.text('Student requests awaiting review'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
      expect(find.textContaining('Nothing is sent by email'), findsOneWidget);
    });
  });

  group('applications list', () {
    final apps = [
      fakeLeave(id: 'a'),
      fakeLeave(
        id: 'b',
        subjectName: 'Bina Kumar',
        subjectId: 'stu-2',
        status: LeaveStatus.approved,
      ),
    ];

    testWidgets('lists applications, passes the chosen status to the query', (
      tester,
    ) async {
      final repo = FakeLeaveApplicationRepository(applications: apps);
      final w = await _pump(tester, role: UserRole.branchAdmin, apps: repo);
      await w.go(tester, '/leave/applications');
      expect(find.textContaining('Anil Kumar'), findsOneWidget);
      expect(find.textContaining('Bina Kumar'), findsOneWidget);
      expect(repo.filters.last.kind, LeaveKind.student);
      expect(repo.filters.last.status, isNull);

      await w.go(tester, '/leave/applications?status=PENDING');
      expect(repo.filters.last.status, LeaveStatus.pending);
      expect(find.textContaining('Bina Kumar'), findsNothing);
    });

    testWidgets('an empty list says so', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/applications');
      expect(
        find.text('No leave applications match these filters.'),
        findsOneWidget,
      );
    });

    testWidgets('a failure is friendly, never the raw error', (tester) async {
      final bad = FakeLeaveApplicationRepository()
        ..error = StateError('raw internal detail');
      final w = await _pump(tester, role: UserRole.branchAdmin, apps: bad);
      await w.go(tester, '/leave/applications');
      expect(find.textContaining('raw internal detail'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
    });

    for (final size in [
      const Size(360, 800),
      const Size(800, 1000),
      const Size(1400, 900),
    ]) {
      testWidgets('no overflow at ${size.width.toInt()}px', (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          apps: FakeLeaveApplicationRepository(applications: apps),
          size: size,
        );
        await w.go(tester, '/leave/applications');
        expect(find.textContaining('Anil Kumar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('review actions follow permissions and ownership', () {
    Future<_World> open(
      WidgetTester tester,
      UserRole role,
      LeaveApplication a, {
      FakeLeaveApplicationRepository? repo,
      String path = '/leave/applications/lv-1',
      String? parent,
    }) async {
      final r = repo ?? FakeLeaveApplicationRepository(applications: [a]);
      final w = await _pump(
        tester,
        role: role,
        apps: r,
        linkedParentId: parent,
        children: [child],
      );
      await w.go(tester, path);
      return w;
    }

    testWidgets(
      'a reviewer sees Approve / Return / Reject on a pending application',
      (tester) async {
        await open(tester, UserRole.branchAdmin, fakeLeave());
        expect(find.text('Approve'), findsOneWidget);
        expect(find.text('Return'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        expect(find.text('Withdraw'), findsNothing);
      },
    );

    testWidgets('a reviewer cannot decide their own application', (
      tester,
    ) async {
      await open(tester, UserRole.branchAdmin, fakeLeave(applicant: _uid));
      expect(find.text('Approve'), findsNothing);
      expect(
        find.textContaining('another reviewer must decide'),
        findsOneWidget,
      );
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets(
      'approving asks to confirm, then records one decision by this reviewer',
      (tester) async {
        final repo = FakeLeaveApplicationRepository(
          applications: [fakeLeave()],
        );
        await open(tester, UserRole.branchAdmin, fakeLeave(), repo: repo);
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        expect(find.text('Approve this leave?'), findsOneWidget);
        expect(
          repo.decisions,
          isEmpty,
          reason: 'nothing happens before confirming',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
        await tester.pumpAndSettle();
        expect(repo.decisions, hasLength(1));
        expect(repo.decisions.single.target, LeaveStatus.approved);
        expect(repo.decisions.single.reviewer, _uid);
        expect(find.text('Leave approved.'), findsOneWidget);
      },
    );

    testWidgets('rejection and return need a reason before anything is sent', (
      tester,
    ) async {
      final repo = FakeLeaveApplicationRepository(applications: [fakeLeave()]);
      await open(tester, UserRole.branchAdmin, fakeLeave(), repo: repo);
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
      await tester.pumpAndSettle();
      expect(find.text('Give a reason.'), findsOneWidget);
      expect(repo.decisions, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'Exams that week');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject').last);
      await tester.pumpAndSettle();
      expect(repo.decisions.single.target, LeaveStatus.rejected);
      expect(repo.decisions.single.remarks, 'Exams that week');
    });

    testWidgets('a refused decision shows the reason; no raw error', (
      tester,
    ) async {
      final repo = FakeLeaveApplicationRepository(applications: [fakeLeave()])
        ..error = const ConflictFailure();
      await open(tester, UserRole.branchAdmin, fakeLeave(), repo: repo);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('changed by someone else'), findsOneWidget);
    });

    testWidgets('approved leave offers cancellation, with a reason', (
      tester,
    ) async {
      final a = fakeLeave(status: LeaveStatus.approved);
      final repo = FakeLeaveApplicationRepository(applications: [a]);
      await open(tester, UserRole.branchAdmin, a, repo: repo);
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Cancel approved leave'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Attendance already recorded is not changed'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'Child will attend');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel leave'));
      await tester.pumpAndSettle();
      expect(repo.cancellations.single.remarks, 'Child will attend');
    });

    testWidgets('a decided application offers no further decisions', (
      tester,
    ) async {
      final apps = [
        fakeLeave(id: 'r', status: LeaveStatus.rejected),
        fakeLeave(id: 'w', status: LeaveStatus.withdrawn),
        fakeLeave(id: 'c', status: LeaveStatus.cancelled),
      ];
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        apps: FakeLeaveApplicationRepository(applications: apps),
      );
      for (final a in apps) {
        await w.go(tester, '/leave/applications/${a.applicationId}');
        expect(find.text('Approve'), findsNothing, reason: a.status.name);
        expect(find.text('Cancel approved leave'), findsNothing);
        expect(find.text('Reject'), findsNothing);
      }
    });

    testWidgets(
      'the parent who applied can withdraw a pending application, once confirmed',
      (tester) async {
        final a = fakeLeave(applicant: _uid);
        final repo = FakeLeaveApplicationRepository(applications: [a]);
        await open(
          tester,
          UserRole.parent,
          a,
          repo: repo,
          path: '/my-leave/applications/lv-1?b=main',
          parent: 'parent-1',
        );
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Withdraw'), findsOneWidget);
        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
        await tester.pumpAndSettle();
        expect(repo.withdrawn.single.applicationId, 'lv-1');
      },
    );

    testWidgets(
      'an approved application cannot be withdrawn by the applicant',
      (tester) async {
        await open(
          tester,
          UserRole.parent,
          fakeLeave(applicant: _uid, status: LeaveStatus.approved),
          path: '/my-leave/applications/lv-1?b=main',
          parent: 'parent-1',
        );
        expect(find.text('Withdraw'), findsNothing);
      },
    );

    testWidgets(
      'a returned application shows the reviewer note and offers correction',
      (tester) async {
        await open(
          tester,
          UserRole.parent,
          fakeLeave(
            applicant: _uid,
            status: LeaveStatus.returned,
            decisionRemarks: 'Please add the doctor note',
          ),
          path: '/my-leave/applications/lv-1?b=main',
          parent: 'parent-1',
        );
        expect(find.text('Please add the doctor note'), findsOneWidget);
        expect(find.text('Correct and resubmit'), findsOneWidget);
      },
    );

    testWidgets('history is listed and shows who decided', (tester) async {
      final repo =
          FakeLeaveApplicationRepository(
              applications: [fakeLeave(status: LeaveStatus.approved)],
            )
            ..history = [
              const LeaveHistoryEntry(
                applicationId: 'lv-1',
                revision: 1,
                from: null,
                to: LeaveStatus.pending,
                event: LeaveEvent.submit,
                actorId: 'u-parent',
                actorName: 'Parent',
              ),
              const LeaveHistoryEntry(
                applicationId: 'lv-1',
                revision: 2,
                from: LeaveStatus.pending,
                to: LeaveStatus.approved,
                event: LeaveEvent.approve,
                actorId: 'admin',
                actorName: 'Principal',
                remarks: 'Get well soon',
              ),
            ];
      await open(
        tester,
        UserRole.branchAdmin,
        fakeLeave(status: LeaveStatus.approved),
        repo: repo,
      );
      expect(find.textContaining('Pending → Approved'), findsOneWidget);
      expect(find.text('Get well soon'), findsOneWidget);
    });

    testWidgets('a missing application says so', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/applications/nope');
      expect(
        find.text('This leave application could not be found.'),
        findsOneWidget,
      );
    });
  });

  group('parent applies for a linked child', () {
    Future<_World> start(
      WidgetTester tester, {
      FakeLeaveApplicationRepository? repo,
      Size size = const Size(1400, 1000),
    }) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child],
        apps: repo,
        size: size,
      );
      await w.go(tester, '/my-leave/apply?studentId=stu-1&b=main');
      return w;
    }

    testWidgets(
      'shows the counted days before submitting, then files exactly one application',
      (tester) async {
        final w = await start(tester);
        expect(find.text('Leave for Anil Kumar'), findsOneWidget);
        await _fillStudentForm(tester);
        expect(find.text('This application counts as 2 days.'), findsOneWidget);

        await tester.tap(_filled('Submit application'));
        await tester.pumpAndSettle();
        expect(w.apps.submitted, hasLength(1));
        final s = w.apps.submitted.single;
        expect(s.subjectId, 'stu-1');
        expect(s.kind, LeaveKind.student);
        expect(s.units, 4);
        expect(s.relation, ApplicantRelation.parent);
        expect(s.applicantUserId, _uid);
        expect(s.typeId, 'STUDENT__sick');
        expect(s.startDateKey, _key(15));
        expect(s.endDateKey, _key(16));
        expect(s.applicationId, startsWith('lv_'));
        expect(
          find.text('Leave application submitted for approval.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Submit stays disabled until type, dates and reason are valid',
      (tester) async {
        await start(tester);
        expect(
          tester.widget<FilledButton>(_filled('Submit application')).onPressed,
          isNull,
        );
        await _chooseType(tester, 'Sick leave');
        expect(find.text('Choose the dates.'), findsOneWidget);
        await _pickDay(tester, 'First day', 15);
        expect(find.text('Please give a reason.'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_filled('Submit application')).onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'a type that needs a document blocks submission until one is attached',
      (tester) async {
        await start(tester);
        await _chooseType(tester, 'Medical');
        await _pickDay(tester, 'First day', 15);
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Surgery',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('A supporting document is required for Medical'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(_filled('Submit application')).onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'overlapping an existing application is refused before sending',
      (tester) async {
        final existing = LeaveApplication(
          applicationId: 'old',
          schoolId: 'school-1',
          branchId: 'main',
          kind: LeaveKind.student,
          subjectId: 'stu-1',
          subjectName: 'Anil Kumar',
          applicantUserId: _uid,
          applicantName: 'P',
          relation: ApplicantRelation.parent,
          typeId: 'STUDENT__sick',
          typeName: 'Sick leave',
          payType: LeavePayType.notApplicable,
          startDateKey: _key(16),
          endDateKey: _key(17),
          units: 4,
          countedDateKeys: [_key(16), _key(17)],
          status: LeaveStatus.approved,
        );
        final w = await start(
          tester,
          repo: FakeLeaveApplicationRepository(applications: [existing]),
        );
        await _fillStudentForm(tester);
        expect(
          find.textContaining('overlaps an existing approved application'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(_filled('Submit application')).onPressed,
          isNull,
        );
        expect(w.apps.submitted, isEmpty);
      },
    );

    testWidgets(
      'a failed submit keeps the form and a retry reuses the SAME application id',
      (tester) async {
        final repo = FakeLeaveApplicationRepository()
          ..error = const NetworkFailure();
        final w = await start(tester, repo: repo);
        await _fillStudentForm(tester);
        await tester.tap(_filled('Submit application'));
        await tester.pumpAndSettle();
        expect(find.textContaining('No internet connection'), findsOneWidget);
        expect(w.apps.submitted, hasLength(1));

        await tester.tap(_filled('Submit application'));
        await tester.pumpAndSettle();
        expect(w.apps.submitted, hasLength(2));
        expect(
          w.apps.submitted.first.applicationId,
          w.apps.submitted.last.applicationId,
        );
        expect(
          find.text('Leave application submitted for approval.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a double tap while saving sends one request', (tester) async {
      final gate = Completer<void>();
      final repo = FakeLeaveApplicationRepository()..gate = () => gate.future;
      final w = await start(tester, repo: repo);
      await _fillStudentForm(tester);
      await tester.tap(_filled('Submit application'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_filled('Submit application')).onPressed,
        isNull,
        reason: 'disabled while the first request is in flight',
      );
      await tester.tap(_filled('Submit application'), warnIfMissed: false);
      await tester.pump();
      expect(w.apps.submitted, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(w.apps.submitted, hasLength(1));
    });

    testWidgets(
      'an id that is not one of the parent\'s linked children is refused',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'parent-1',
          children: [child],
        );
        await w.go(tester, '/my-leave/apply?studentId=someone-else&b=main');
        expect(
          find.textContaining('Choose one of your linked children'),
          findsOneWidget,
        );
        expect(find.text('Submit application'), findsNothing);
      },
    );

    testWidgets(
      'a school calendar that cannot be read stops the form, with the reason',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'parent-1',
          children: [child],
          schoolCalendar: FakeCalendarRepository()
            ..error = const PermissionFailure(),
        );
        await w.go(tester, '/my-leave/apply?studentId=stu-1&b=main');
        expect(find.textContaining('permission'), findsOneWidget);
        // Never an unchecked form that would count every day as a leave day.
        expect(find.text('Submit application'), findsNothing);
        expect(w.apps.submitted, isEmpty);
      },
    );

    testWidgets('no overflow on a phone', (tester) async {
      await start(tester, size: const Size(360, 800));
      await _fillStudentForm(tester);
      expect(find.text('This application counts as 2 days.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('my leave (parent and staff)', () {
    testWidgets('a parent sees their child\'s applications, read-only', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child],
        apps: FakeLeaveApplicationRepository(
          applications: [
            fakeLeave(applicant: _uid),
            fakeLeave(
              id: 'lv-2',
              status: LeaveStatus.approved,
              applicant: _uid,
              start: '2026-09-01',
              end: '2026-09-01',
              units: 2,
            ),
          ],
        ),
      );
      await w.go(tester, '/my-leave');
      expect(find.text('Leave for Anil Kumar'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Apply for leave'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('a parent with no linked record is told why', (tester) async {
      final w = await _pump(tester, role: UserRole.parent);
      await w.go(tester, '/my-leave');
      expect(
        find.textContaining("isn't linked to a parent record"),
        findsOneWidget,
      );
    });

    testWidgets('staff see their balances and applications', (tester) async {
      final balance = LeaveBalance(
        balanceId: LeaveBalance.idFor('s9', 'STAFF__cl', 'y1'),
        schoolId: 'school-1',
        branchId: 'main',
        staffId: 's9',
        typeId: 'STAFF__cl',
        academicYearId: 'y1',
        leaveYearStartKey: '2026-06-01',
        entitlementUnits: 24,
        consumedUnits: 6,
      );
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        staffRecord: true,
        balances: FakeLeaveBalanceRepository(balances: [balance]),
        apps: FakeLeaveApplicationRepository(
          applications: [
            fakeLeave(
              kind: LeaveKind.staff,
              subjectId: 's9',
              subjectName: 'Priya Iyer',
              applicant: _uid,
              typeId: 'STAFF__cl',
              typeName: 'Casual leave',
              pay: LeavePayType.paid,
              balanceId: balance.balanceId,
            ),
          ],
        ),
      );
      await w.go(tester, '/my-leave');
      expect(find.text('Casual leave'), findsWidgets);
      expect(find.text('9 days'), findsOneWidget); // 24 - 6 units = 18 units
      expect(find.text('available'), findsOneWidget);
      expect(find.textContaining('Granted 12'), findsOneWidget);
    });

    testWidgets(
      'a staff login without a staff record cannot apply, and says why',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/my-leave');
        expect(
          find.textContaining("isn't linked to a staff record"),
          findsOneWidget,
        );
        expect(find.text('Apply for leave'), findsNothing);
      },
    );
  });

  group('staff applies', () {
    LeaveBalance balance({int consumed = 0}) => LeaveBalance(
      balanceId: LeaveBalance.idFor('s9', 'STAFF__cl', 'y1'),
      schoolId: 'school-1',
      branchId: 'main',
      staffId: 's9',
      typeId: 'STAFF__cl',
      academicYearId: 'y1',
      leaveYearStartKey: '${DateTime.now().year - 1}-01-01',
      entitlementUnits: 24,
      consumedUnits: consumed,
    );

    testWidgets(
      'files for themselves with the balance link; the staff id comes from their own record',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          staffRecord: true,
          balances: FakeLeaveBalanceRepository(balances: [balance()]),
        );
        await w.go(tester, '/my-leave/apply');
        await _chooseType(tester, 'Casual leave');
        await _pickDay(tester, 'First day', 15);
        await _pickDay(tester, 'Last day', 16);
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Family event',
        );
        await tester.pumpAndSettle();
        await tester.tap(_filled('Submit application'));
        await tester.pumpAndSettle();
        final s = w.apps.submitted.single;
        expect(s.kind, LeaveKind.staff);
        expect(s.subjectId, 's9');
        expect(s.relation, ApplicantRelation.self);
        expect(s.balanceId, 's9__STAFF__cl__y1');
        expect(s.units, 4);
      },
    );

    testWidgets(
      'over the balance under BLOCK: refused with the figures, nothing sent',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          staffRecord: true,
          balances: FakeLeaveBalanceRepository(
            balances: [balance(consumed: 22)],
          ),
        );
        await w.go(tester, '/my-leave/apply');
        await _chooseType(tester, 'Casual leave');
        await _pickDay(tester, 'First day', 15);
        await _pickDay(tester, 'Last day', 16);
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Family event',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('only 1 day is available'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_filled('Submit application')).onPressed,
          isNull,
        );
        expect(w.apps.submitted, isEmpty);
      },
    );
  });

  group('leave types and policy', () {
    testWidgets(
      'an admin creates a student type; code and name are validated',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/leave/types');
        expect(find.text('Sick leave (SICK)'), findsOneWidget);
        await tester.tap(find.text('Add leave type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('2-20 letters, digits, "-" or "_".'), findsOneWidget);
        expect(find.text('Enter a name.'), findsOneWidget);
        expect(w.types.saved, isEmpty);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Code'),
          'FAMILY',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Family function',
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final t = w.types.saved.single;
        expect(t.typeId, 'STUDENT__family');
        expect(t.kind, LeaveKind.student);
        expect(t.payType, LeavePayType.notApplicable);
        expect(t.annualEntitlementUnits, isNull);
      },
    );

    testWidgets('a staff type stores the entitlement as half-day units', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/types');
      await tester.tap(find.text('Staff leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add leave type'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Code'),
        'EARNED',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Earned leave',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Annual entitlement (days)'),
        '7.5',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final t = w.types.saved.single;
      expect(t.kind, LeaveKind.staff);
      expect(t.payType, LeavePayType.paid);
      expect(t.annualEntitlementUnits, 15);
    });

    testWidgets('an entitlement that is not a half-day multiple is refused', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/types');
      await tester.tap(find.text('Staff leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add leave type'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Code'),
        'EARNED',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Earned leave',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Annual entitlement (days)'),
        '7.3',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('whole or half days'), findsOneWidget);
      expect(w.types.saved, isEmpty);
    });

    testWidgets('the on-behalf policy switch is shown and stored', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/types');
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(w.types.allowOnBehalf, isTrue);
    });
  });

  group('calendar', () {
    LeaveCalendarEntry entry(
      String id,
      String name, {
      LeaveKind kind = LeaveKind.student,
    }) {
      final today = DateTime.now();
      final key = '${today.year}-${_pad(today.month)}-${_pad(today.day)}';
      return LeaveCalendarEntry(
        applicationId: id,
        schoolId: 'school-1',
        branchId: 'main',
        kind: kind,
        subjectId: id,
        subjectName: name,
        startDateKey: key,
        endDateKey: key,
        countedDateKeys: [key],
      );
    }

    testWidgets('shows who is away on a day, with no reason or type', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        calendar: FakeLeaveCalendarRepository(
          entries: [entry('1', 'Anil Kumar'), entry('2', 'Bina Kumar')],
        ),
      );
      await w.go(tester, '/leave/calendar');
      expect(find.text('2 away'), findsOneWidget);
      await tester.tap(find.text('2 away'));
      await tester.pumpAndSettle();
      expect(find.text('Anil Kumar'), findsOneWidget);
      expect(find.text('Bina Kumar'), findsOneWidget);
      expect(find.textContaining('Fever'), findsNothing);
    });

    testWidgets('a teacher sees students only — no staff switch', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, staffRecord: true);
      await w.go(tester, '/leave/calendar');
      expect(find.byType(SegmentedButton<LeaveKind>), findsNothing);
      expect(w.calendar.queries.last.kind, LeaveKind.student);
      // …for a section they teach, class AND section pinned (the rules refuse
      // anything wider).
      expect(w.calendar.queries.last.classId, 'c5');
      expect(w.calendar.queries.last.sectionId, 'sa');
    });

    testWidgets('a failure is friendly with retry', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        calendar: FakeLeaveCalendarRepository()
          ..error = StateError('internal path /x'),
      );
      await w.go(tester, '/leave/calendar');
      expect(find.textContaining('internal path'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('reports and notifications', () {
    testWidgets('report numbers come from the aggregate repository', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/leave/reports');
      expect(find.text('7'), findsOneWidget); // approved
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Sick leave'), findsWidgets);
    });

    testWidgets('notifications show newest first and mark one read on open', (
      tester,
    ) async {
      final notices = FakeLeaveNotificationRepository(
        forUser: const [
          LeaveNotification(
            notificationId: 'n1',
            type: 'LEAVE_APPROVED',
            applicationId: 'lv-1',
            title: 'Leave approved',
            body: 'Anil Kumar · 15/08/2026',
            read: false,
          ),
        ],
      );
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child],
        notices: notices,
        apps: FakeLeaveApplicationRepository(
          applications: [
            fakeLeave(applicant: _uid, status: LeaveStatus.approved),
          ],
        ),
      );
      await w.go(tester, '/my-leave/notifications');
      expect(find.text('Leave approved'), findsOneWidget);
      await tester.tap(find.text('Leave approved'));
      await tester.pumpAndSettle();
      expect(notices.marked, ['n1']);
    });

    testWidgets('an empty inbox says so', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child],
      );
      await w.go(tester, '/my-leave/notifications');
      expect(find.text('No notifications yet.'), findsOneWidget);
    });
  });
}
