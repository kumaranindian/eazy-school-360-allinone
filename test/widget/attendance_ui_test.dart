import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/presentation/providers/leave_providers.dart';
import 'dart:async';

import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_day.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_registers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_tally.dart';
import 'package:eazy_school_360/features/attendance/presentation/providers/attendance_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/leave_fakes.dart';
import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'o@r.example',
  status: SchoolStatus.active,
);
const _branch = Branch(
  branchId: 'main',
  schoolId: 'school-1',
  name: 'Main',
  status: BranchStatus.active,
);

UserProfile _profile(UserRole role) => UserProfile(
  userId: _uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: 'Grace Hopper',
  email: 'g@example.com',
  role: role,
  status: UserStatus.active,
);

final _today = AttendanceDate.dateOnly(DateTime.now());
final _todayKey = AttendanceDate.key(_today);

final _year = AcademicYear(
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime(_today.year, 1, 1),
  endDate: DateTime(_today.year, 12, 31),
  status: AcademicYearStatus.active,
);

FakeAcademicStructureRepository _academic() => FakeAcademicStructureRepository(
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
    for (final (id, name) in [('sec-a', 'A'), ('sec-b', 'B')])
      Section(
        sectionId: id,
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'y1',
        classId: 'c5',
        name: name,
        status: ActivationStatus.active,
      ),
  ],
);

StudentRegister _register({
  AttendanceDay? day,
  Map<String, AttendanceStatus> stored = const {},
}) {
  final students = [
    fakeStudent('1', 'Anil', roll: '1'),
    fakeStudent('2', 'Bina', roll: '2'),
    fakeStudent('3', 'Charu', roll: '3'),
  ];
  return StudentRegister(
    roster: [
      for (final s in students)
        EnrolledStudent(student: s, academicRecordId: 'rec-${s.studentId}'),
    ],
    records: {
      for (final e in stored.entries)
        e.key: fakeStoredAttendance(e.key, dateKey: _todayKey, status: e.value),
    },
    day: day,
  );
}

AttendanceDay _day({bool finalized = false, int revision = 1}) => AttendanceDay(
  dayId: '${_todayKey}__y1__c5__sec-a',
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: 'sec-a',
  dateKey: _todayKey,
  status: finalized ? AttendanceDayStatus.finalized : AttendanceDayStatus.draft,
  tally: const AttendanceTally(present: 3),
  revision: revision,
);

class _World {
  final ProviderContainer container;
  final FakeStudentAttendanceRepository students;
  final FakeStaffAttendanceRepository staff;

  _World(this.container, this.students, this.staff);

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  Future<void> go(WidgetTester tester, String path) async {
    container.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
  }
}

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  StudentRegister? register,
  FakeCalendarRepository? calendar,
  List<AttendanceDay> sessions = const [],
  Size size = const Size(1400, 1000),
  bool classTeacher = true,
  FakeLeaveCalendarRepository? leave,
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final students = FakeStudentAttendanceRepository(
    register: register ?? _register(),
    sessions: sessions,
  );
  final staff = FakeStaffAttendanceRepository(
    register: StaffRegister(
      roster: [attendanceStaff('t1', 'Meera'), attendanceStaff('t2', 'Nikhil')],
      records: const {},
      day: null,
    ),
  );

  final me = fakeStaff(
    's9',
    first: 'Priya',
    last: 'Iyer',
    isTeacher: true,
    userId: _uid,
  );
  final assignments = FakeTeacherAssignmentRepository()
    ..existing = classTeacher
        ? [
            TeacherAssignment(
              assignmentId: 'a1',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              teacherStaffId: 's9',
              classId: 'c5',
              sectionId: 'sec-a',
              isClassTeacher: true,
              startDate: DateTime(2026, 6, 1),
              status: TeacherAssignmentStatus.active,
            ),
          ]
        : [];

  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'g@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({_uid: _profile(role)}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {'school-1/main': _branch},
        ),
      ),
      academicStructureRepositoryProvider.overrideWithValue(_academic()),
      calendarRepositoryProvider.overrideWithValue(
        calendar ?? FakeCalendarRepository(),
      ),
      staffRepositoryProvider.overrideWithValue(
        FakeStaffRepository(staff: [me]),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(assignments),
      studentAttendanceRepositoryProvider.overrideWithValue(students),
      leaveCalendarRepositoryProvider.overrideWithValue(
        leave ?? FakeLeaveCalendarRepository(),
      ),
      staffAttendanceRepositoryProvider.overrideWithValue(staff),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, students, staff);
}

Future<void> _selectManagerSection(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'Class'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Class 5').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'Section'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('A').last);
  await tester.pumpAndSettle();
}

Finder get _saveButton => find
    .ancestor(
      of: find.textContaining('Save'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;
void main() {
  group('route and navigation permissions', () {
    testWidgets('a parent can open nothing under /attendance', (tester) async {
      final w = await _pump(tester, role: UserRole.parent);
      for (final p in [
        '/attendance',
        '/attendance/students',
        '/attendance/staff',
        '/attendance/reports',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
      expect(find.text('Attendance'), findsNothing);
    });

    testWidgets(
      'a teacher can mark students and see reports but cannot open staff attendance',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');
        expect(w.location, '/attendance/students');
        await w.go(tester, '/attendance/reports');
        expect(w.location, '/attendance/reports');
        await w.go(tester, '/attendance/staff');
        expect(w.location, '/dashboard');
      },
    );

    testWidgets(
      'finance can see the hub, staff attendance and reports but not mark students',
      (tester) async {
        final w = await _pump(tester, role: UserRole.finance);
        await w.go(tester, '/attendance');
        expect(w.location, '/attendance');
        await w.go(tester, '/attendance/staff');
        expect(w.location, '/attendance/staff');
        await w.go(tester, '/attendance/students');
        expect(w.location, '/dashboard');
      },
    );

    testWidgets('a branch admin can open everything', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      for (final p in [
        '/attendance',
        '/attendance/students',
        '/attendance/staff',
        '/attendance/reports',
      ]) {
        await w.go(tester, p);
        expect(w.location, p);
      }
    });
  });

  group('teacher marking a class', () {
    testWidgets(
      'a class teacher is taken straight to their own section — no other class is offered',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');

        expect(find.textContaining('Class 5 · Section A'), findsOneWidget);
        expect(find.text('Anil Kumar'), findsOneWidget);
        expect(find.textContaining('Section B'), findsNothing);
        expect(w.students.loads, 1);
      },
    );

    testWidgets(
      'a teacher who is class teacher of nothing is told so and cannot mark anything',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          classTeacher: false,
        );
        await w.go(tester, '/attendance/students');
        expect(
          find.textContaining("aren't the class teacher of any section"),
          findsOneWidget,
        );
        expect(find.text('Anil Kumar'), findsNothing);
      },
    );

    testWidgets(
      'nobody is pre-marked; the summary starts at everyone not marked',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');
        expect(find.text('Not marked: 3'), findsOneWidget);
        expect(find.text('Present: 0'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_saveButton).onPressed,
          isNull,
          reason: 'nothing to save yet',
        );
      },
    );

    testWidgets(
      'mark all present, make one exception, save: one request with every student and the right totals',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');

        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        expect(find.text('Present: 3'), findsOneWidget);

        await tester.tap(
          find
              .descendant(
                of: find.widgetWithText(Container, 'Bina Kumar').first,
                matching: find.text('A'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Present: 2'), findsOneWidget);
        expect(find.text('Absent: 1'), findsOneWidget);

        await tester.tap(_saveButton);
        await tester.pumpAndSettle();

        expect(w.students.saves, hasLength(1));
        final request = w.students.saves.single;
        expect(request.dateKey, _todayKey);
        expect(
          [request.academicYearId, request.classId, request.sectionId],
          ['y1', 'c5', 'sec-a'],
        );
        expect(request.finalize, isFalse);
        expect(request.actorId, _uid);
        expect(request.expectedDayRevision, 0);
        expect(
          {for (final e in request.entries) e.subjectId: e.status},
          {
            '1': AttendanceStatus.present,
            '2': AttendanceStatus.absent,
            '3': AttendanceStatus.present,
          },
        );
        expect(find.text('Attendance saved successfully.'), findsOneWidget);
        expect(w.students.loads, 2, reason: 'reloads after a successful save');
      },
    );

    testWidgets(
      'saving with someone unmarked asks first; cancel saves nothing, confirm saves partial attendance',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');
        await tester.tap(
          find
              .descendant(
                of: find.widgetWithText(Container, 'Anil Kumar').first,
                matching: find.text('P'),
              )
              .first,
        );
        await tester.pumpAndSettle();

        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        expect(find.text('Save partial attendance?'), findsOneWidget);
        expect(find.textContaining('2 of 3 are not marked'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(w.students.saves, isEmpty);

        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save partial'));
        await tester.pumpAndSettle();
        expect(w.students.saves, hasLength(1));
        expect(
          w.students.saves.single.entries.where((e) => e.status == null),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'finalize is refused while anyone is unmarked, and sends finalize=true once everyone is marked',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/attendance/students');
        await tester.tap(find.text('Finalize'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Mark every entry before finalizing'),
          findsOneWidget,
        );
        expect(w.students.saves, isEmpty);

        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finalize'));
        await tester.pumpAndSettle();
        expect(find.text('Finalize attendance?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Finalize').last);
        await tester.pumpAndSettle();
        expect(w.students.saves.single.finalize, isTrue);
      },
    );

    testWidgets(
      'a double-click on Save sends ONE request while the first is in flight',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        final gate = Completer<void>();
        w.students.saveGate = () => gate.future;
        await w.go(tester, '/attendance/students');
        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();

        await tester.tap(_saveButton);
        await tester.pump();
        await tester.tap(_saveButton, warnIfMissed: false);
        await tester.pump();
        expect(w.students.saves, hasLength(1));
        expect(
          tester.widget<FilledButton>(_saveButton).onPressed,
          isNull,
          reason: 'disabled while saving',
        );

        gate.complete();
        await tester.pumpAndSettle();
        expect(w.students.saves, hasLength(1));
        expect(find.text('Attendance saved successfully.'), findsOneWidget);
      },
    );

    testWidgets(
      'success is NOT announced until the write has actually succeeded',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        final gate = Completer<void>();
        w.students.saveGate = () => gate.future;
        await w.go(tester, '/attendance/students');
        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton);
        await tester.pump();
        expect(find.text('Attendance saved successfully.'), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('Attendance saved successfully.'), findsOneWidget);
      },
    );

    testWidgets(
      'a concurrent edit shows a conflict dialog, writes nothing more, and reloads the latest',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        w.students.saveError = const ConflictFailure(
          'Attendance for Anil Kumar was changed by someone else.',
        );
        await w.go(tester, '/attendance/students');
        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton);
        // The save spinner keeps animating behind the dialog: pump a fixed time.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Changed by someone else'), findsOneWidget);
        expect(find.textContaining('Nothing was saved'), findsOneWidget);
        expect(find.text('Attendance saved successfully.'), findsNothing);
        await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(w.students.loads, 2);
      },
    );

    testWidgets(
      'an unexpected error is shown as a friendly message — never the raw exception — and edits are kept',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        w.students.saveError = StateError(
          'PERMISSION_DENIED: secret rule detail',
        );
        await w.go(tester, '/attendance/students');
        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton);
        await tester.pumpAndSettle();

        expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        expect(
          find.text('Present: 3'),
          findsOneWidget,
          reason: 'the marks are still there to retry',
        );
      },
    );

    testWidgets('an empty class shows an empty state', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        register: const StudentRegister(roster: [], records: {}, day: null),
      );
      await w.go(tester, '/attendance/students');
      expect(find.textContaining('Nobody is enrolled'), findsOneWidget);
    });
  });

  group('finalized attendance', () {
    testWidgets(
      'a teacher sees it locked: banner shown, status buttons and Save disabled',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          register: _register(
            day: _day(finalized: true),
            stored: {
              '1': AttendanceStatus.present,
              '2': AttendanceStatus.present,
              '3': AttendanceStatus.absent,
            },
          ),
        );
        await w.go(tester, '/attendance/students');
        expect(
          find.textContaining('Only a manager can correct'),
          findsOneWidget,
        );
        await tester.tap(
          find
              .descendant(
                of: find.widgetWithText(Container, 'Anil Kumar').first,
                matching: find.text('A'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Absent: 1'),
          findsOneWidget,
          reason: 'unchanged: the tap was ignored',
        );
        expect(find.text('Finalize'), findsNothing);
      },
    );

    testWidgets(
      'a manager can correct it, but is made to give a reason which travels with the request',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          register: _register(
            day: _day(finalized: true, revision: 3),
            stored: {
              '1': AttendanceStatus.present,
              '2': AttendanceStatus.present,
              '3': AttendanceStatus.present,
            },
          ),
        );
        await w.go(tester, '/attendance/students');
        await _selectManagerSection(tester);
        expect(find.textContaining('needs a written reason'), findsOneWidget);

        await tester.tap(
          find
              .descendant(
                of: find.widgetWithText(Container, 'Bina Kumar').first,
                matching: find.text('A'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        expect(find.text('Reason for correction'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Parent confirmed absence',
        );
        await tester.pump();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(w.students.saves, hasLength(1));
        expect(w.students.saves.single.reason, 'Parent confirmed absence');
        expect(w.students.saves.single.expectedDayRevision, 3);
      },
    );
  });

  group('calendar integration', () {
    final holiday = Holiday(
      holidayId: 'h',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y1',
      date: Holiday.normalizeDate(_today),
      name: 'Founders Day',
      type: HolidayType.school,
      status: ActivationStatus.active,
    );

    testWidgets(
      'on a holiday a teacher cannot mark: the day is named and editing is blocked',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          calendar: FakeCalendarRepository(holidays: [holiday]),
        );
        await w.go(tester, '/attendance/students');
        expect(find.textContaining('Holiday: Founders Day'), findsOneWidget);
        expect(
          find.textContaining('cannot be marked on this day'),
          findsOneWidget,
        );
        expect(find.text('Mark all present').hitTestable(), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find
              .ancestor(
                of: find.text('Mark all present'),
                matching: find.byWidgetPredicate((w) => w is OutlinedButton),
              )
              .first,
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('a manager may override a holiday, but only with a reason', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        calendar: FakeCalendarRepository(holidays: [holiday]),
      );
      await w.go(tester, '/attendance/students');
      await _selectManagerSection(tester);
      expect(find.textContaining('authorized override'), findsOneWidget);

      await tester.tap(find.text('Mark all present'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a reason'), findsOneWidget);
      expect(w.students.saves, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Override reason'),
        'Extra revision class',
      );
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(w.students.saves.single.overrideReason, 'Extra revision class');
    });
  });

  group('approved leave is an annotation, never an attendance change', () {
    LeaveCalendarEntry onLeave(
      String studentId, {
      HalfDay half = HalfDay.none,
    }) => LeaveCalendarEntry(
      applicationId: 'lv-$studentId',
      schoolId: 'school-1',
      branchId: 'main',
      kind: LeaveKind.student,
      subjectId: studentId,
      subjectName: 'x',
      sectionId: 'sec-a',
      startDateKey: _todayKey,
      endDateKey: _todayKey,
      halfDay: half,
      countedDateKeys: [_todayKey],
    );

    testWidgets(
      'a student on approved leave is flagged; nobody is marked or changed because of it',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          leave: FakeLeaveCalendarRepository(entries: [onLeave('1')]),
        );
        await w.go(tester, '/attendance/students');

        expect(find.text('On approved leave'), findsOneWidget);
        // Leave does not pre-mark anyone: the register is exactly as before.
        expect(find.text('Not marked: 3'), findsOneWidget);
        expect(find.text('Present: 0'), findsOneWidget);
        expect(find.text('Absent: 0'), findsOneWidget);
        expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
        expect(w.students.saves, isEmpty);
      },
    );

    testWidgets(
      'a half-day leave says which session; an already saved status is shown untouched beside it',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          register: _register(stored: {'1': AttendanceStatus.present}),
          leave: FakeLeaveCalendarRepository(
            entries: [onLeave('1', half: HalfDay.second)],
          ),
        );
        await w.go(tester, '/attendance/students');
        expect(find.text('On approved leave (second half)'), findsOneWidget);
        expect(find.text('Present: 1'), findsOneWidget);
      },
    );

    testWidgets('a cancelled leave shows no annotation', (tester) async {
      final cancelled = LeaveCalendarEntry(
        applicationId: 'lv-1',
        schoolId: 'school-1',
        branchId: 'main',
        kind: LeaveKind.student,
        subjectId: '1',
        subjectName: 'x',
        sectionId: 'sec-a',
        startDateKey: _todayKey,
        endDateKey: _todayKey,
        countedDateKeys: [_todayKey],
        active: false,
      );
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        leave: FakeLeaveCalendarRepository(entries: [cancelled]),
      );
      await w.go(tester, '/attendance/students');
      expect(find.text('On approved leave'), findsNothing);
    });

    testWidgets(
      'a finalized register keeps its status and shows the annotation too',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          register: _register(
            day: _day(finalized: true),
            stored: {'1': AttendanceStatus.absent},
          ),
          leave: FakeLeaveCalendarRepository(entries: [onLeave('1')]),
        );
        await w.go(tester, '/attendance/students');
        expect(find.text('On approved leave'), findsOneWidget);
        expect(find.text('Absent: 1'), findsOneWidget);
        expect(
          find.textContaining('Only a manager can correct'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a failing leave lookup never blocks marking attendance', (
      tester,
    ) async {
      final failing = FakeLeaveCalendarRepository()..error = StateError('boom');
      final w = await _pump(tester, role: UserRole.teacher, leave: failing);
      await w.go(tester, '/attendance/students');
      expect(find.text('Anil Kumar'), findsOneWidget);
      expect(find.text('Not marked: 3'), findsOneWidget);
    });
  });

  group('staff attendance', () {
    testWidgets('a manager marks everyone present and saves', (tester) async {
      final w = await _pump(tester, role: UserRole.schoolAdmin);
      await w.go(tester, '/attendance/staff');
      expect(find.text('Meera Rao'), findsOneWidget);
      expect(find.text('Not marked: 2'), findsOneWidget);
      await tester.tap(find.text('Mark all present'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      final request = w.staff.saves.single;
      expect(request.dateKey, _todayKey);
      expect(request.entries.map((e) => e.status), [
        AttendanceStatus.present,
        AttendanceStatus.present,
      ]);
    });

    testWidgets('finance sees the register read-only: no editing, no save', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.finance);
      await w.go(tester, '/attendance/staff');
      expect(find.text('View only'), findsOneWidget);
      final markAll = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text('Mark all present'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .first,
      );
      expect(markAll.onPressed, isNull);
      expect(w.staff.saves, isEmpty);
    });
  });

  group('attendance hub', () {
    testWidgets(
      'a manager sees real figures from the registers and the sections still pending',
      (tester) async {
        final done = AttendanceDay(
          dayId: 'd',
          schoolId: 'school-1',
          branchId: 'main',
          academicYearId: 'y1',
          classId: 'c5',
          sectionId: 'sec-a',
          dateKey: _todayKey,
          status: AttendanceDayStatus.finalized,
          tally: const AttendanceTally(
            present: 25,
            absent: 3,
            late: 1,
            halfDay: 1,
          ),
        );
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          sessions: [done],
        );
        await w.go(tester, '/attendance');

        expect(find.text('Present: 25'), findsOneWidget);
        expect(find.text('Absent: 3'), findsOneWidget);
        expect(find.text('Late: 1'), findsOneWidget);
        expect(find.text('Half day: 1'), findsOneWidget);
        expect(find.text('Enrolled (marked registers): 30'), findsOneWidget);
        expect(
          find.textContaining('Registers started: 1 of 2'),
          findsOneWidget,
        );
        expect(find.textContaining('Attendance pending (1)'), findsOneWidget);
        expect(find.textContaining('Class 5 B · Not started'), findsOneWidget);
        expect(
          find.textContaining('Class 5 A'),
          findsNothing,
          reason: 'finalized sections are not pending',
        );
      },
    );

    testWidgets(
      'with nothing marked the dashboard says so rather than inventing numbers',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/attendance');
        expect(find.text('Present: 0'), findsOneWidget);
        expect(
          find.textContaining('Registers started: 0 of 2'),
          findsOneWidget,
        );
        expect(
          find.text('Staff attendance has not been marked for this date.'),
          findsOneWidget,
        );
      },
    );
  });

  group('responsive layout', () {
    for (final size in [
      const Size(360, 1600),
      const Size(800, 1400),
      const Size(1400, 900),
    ]) {
      testWidgets('marking screen has no overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        final w = await _pump(tester, role: UserRole.teacher, size: size);
        await w.go(tester, '/attendance/students');
        expect(find.textContaining('Anil Kumar'), findsOneWidget);
        await tester.tap(find.text('Mark all present'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'on a phone the status buttons are at least 44 px tall (large touch targets)',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          size: const Size(360, 1600),
        );
        await w.go(tester, '/attendance/students');
        final inkWell = find
            .ancestor(of: find.text('P').first, matching: find.byType(InkWell))
            .first;
        expect(tester.getSize(inkWell).height, greaterThanOrEqualTo(44));
      },
    );
  });
}
