import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings_repository.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_settings_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/presentation/providers/leave_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/timetable/domain/period_set.dart';
import 'package:eazy_school_360/features/timetable/domain/substitution.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_enums.dart';
import 'package:eazy_school_360/features/timetable/presentation/providers/timetable_providers.dart';
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
import '../support/timetable_fakes.dart';

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
  }) async => children;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PeriodSlot _p(String id, int n, int s, int e) => PeriodSlot(
  slotId: id,
  number: n,
  kind: SlotKind.teaching,
  label: '',
  startMin: s,
  endMin: e,
);

PeriodSet _set() => PeriodSet(
  periodSetId: 'y1__regular',
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  name: 'Regular',
  slots: [
    _p('p1', 1, 540, 580),
    const PeriodSlot(
      slotId: 'brk',
      kind: SlotKind.breakSlot,
      label: 'Break',
      startMin: 580,
      endMin: 590,
    ),
    _p('p2', 2, 590, 630),
  ],
);

final _allDays = {for (final d in Weekday.values) d.wireValue: 'y1__regular'};

Timetable _tt(
  String section, {
  int version = 1,
  TimetableStatus status = TimetableStatus.published,
  String from = '2020-01-01',
  String? to,
  Map<String, String>? days,
  int entryCount = 0,
}) => Timetable(
  timetableId: Timetable.idFor('y1__c5__$section', version),
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: section,
  className: 'Class 5',
  sectionName: section.toUpperCase(),
  name: 'Term 1',
  version: version,
  status: status,
  dayPeriodSets: days ?? _allDays,
  effectiveFromKey: from,
  effectiveToKey: to,
  entryCount: entryCount,
);

/// One period-1 cell on every weekday for [teacher].
List<TimetableEntry> _cells(
  Timetable t,
  String subject,
  String teacher,
  String teacherName, {
  String slot = 'p1',
  int period = 1,
  int start = 540,
  int end = 580,
  String? room,
}) => [
  for (final d in Weekday.values)
    TimetableEntry(
      entryId: TimetableEntry.idFor(t.timetableId, d, slot),
      timetableId: t.timetableId,
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y1',
      classId: t.classId,
      sectionId: t.sectionId,
      weekday: d,
      slotId: slot,
      periodNumber: period,
      startMin: start,
      endMin: end,
      subjectId: subject,
      subjectName: subject == 'math' ? 'Maths' : 'English',
      teacherStaffId: teacher,
      teacherName: teacherName,
      room: room,
      live: true,
    ),
];

TeacherAssignment _assign(String teacher, String section, String subject) =>
    TeacherAssignment(
      assignmentId: 'a-$teacher-$section-$subject',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y1',
      teacherStaffId: teacher,
      classId: 'c5',
      sectionId: section,
      subjectId: subject,
      isClassTeacher: false,
      startDate: DateTime(2026, 6, 1),
      status: TeacherAssignmentStatus.active,
    );

class _World {
  final ProviderContainer container;
  final FakeTimetableRepository timetables;
  final FakeSubstitutionRepository substitutions;
  final FakePeriodSetRepository periodSets;

  _World(this.container, this.timetables, this.substitutions, this.periodSets);

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
  FakeTimetableRepository? timetables,
  FakeSubstitutionRepository? substitutions,
  FakePeriodSetRepository? periodSets,
  FakeLeaveCalendarRepository? leave,
  List<TeacherAssignment>? assignments,
  List<Student> children = const [],
  String? linkedParentId,
  String? ownStaffId,
  Size size = const Size(1400, 1000),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final tts = timetables ?? FakeTimetableRepository();
  final subs = substitutions ?? FakeSubstitutionRepository();
  final sets = periodSets ?? FakePeriodSetRepository(sets: [_set()]);
  final teacherAssignments = FakeTeacherAssignmentRepository()
    ..existing =
        assignments ??
        [
          _assign('t1', 'sa', 'math'),
          _assign('t2', 'sa', 'eng'),
          _assign('t3', 'sb', 'math'),
        ];

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
            for (final s in ['sa', 'sb'])
              Section(
                sectionId: s,
                schoolId: 'school-1',
                branchId: 'main',
                academicYearId: 'y1',
                classId: 'c5',
                name: s.toUpperCase(),
                status: ActivationStatus.active,
              ),
          ],
          subjects: [
            for (final (id, name) in [('math', 'Maths'), ('eng', 'English')])
              Subject(
                subjectId: id,
                schoolId: 'school-1',
                branchId: 'main',
                academicYearId: 'y1',
                name: name,
                type: SubjectType.core,
                displayOrder: 1,
                status: ActivationStatus.active,
              ),
          ],
        ),
      ),
      academicSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      calendarRepositoryProvider.overrideWithValue(
        FakeCalendarRepository(workingDays: null),
      ),
      parentRepositoryProvider.overrideWithValue(
        _FakeParentRepository(children),
      ),
      staffRepositoryProvider.overrideWithValue(
        FakeStaffRepository(
          staff: [
            fakeStaff(
              't1',
              first: 'Meera',
              last: 'Iyer',
              isTeacher: true,
              userId: ownStaffId == 't1' ? _uid : 'u-t1',
            ),
            fakeStaff(
              't2',
              first: 'Nikhil',
              last: 'Rao',
              isTeacher: true,
              userId: 'u-t2',
            ),
            fakeStaff(
              't3',
              first: 'Omar',
              last: 'Khan',
              isTeacher: true,
              userId: 'u-t3',
            ),
          ],
        ),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(teacherAssignments),
      leaveCalendarRepositoryProvider.overrideWithValue(
        leave ?? FakeLeaveCalendarRepository(),
      ),
      periodSetRepositoryProvider.overrideWithValue(sets),
      timetableRepositoryProvider.overrideWithValue(tts),
      substitutionRepositoryProvider.overrideWithValue(subs),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, tts, subs, sets);
}

Finder _filled(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;

String _today() => AttendanceDate.key(DateTime.now());

Substitution _cover({
  String date = '2026-01-05',
  String? leaveId,
  Timetable? t,
  String substitute = 't2',
  SubstitutionStatus status = SubstitutionStatus.active,
}) {
  final tt = t ?? _tt('sa');
  final cell = _cells(tt, 'math', 't1', 'Meera Iyer').first;
  return Substitution(
    substitutionId: Substitution.idFor(date, tt.timetableId, 'p1'),
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: 'y1',
    dateKey: date,
    timetableId: tt.timetableId,
    timetableVersion: tt.version,
    entryId: cell.entryId,
    slotId: 'p1',
    weekday: Weekday.monday,
    periodNumber: 1,
    startMin: 540,
    endMin: 580,
    classId: 'c5',
    sectionId: tt.sectionId,
    classLabel: tt.title,
    subjectId: 'math',
    subjectName: 'Maths',
    originalTeacherId: 't1',
    originalTeacherName: 'Meera Iyer',
    substituteTeacherId: substitute,
    substituteTeacherName: 'Nikhil Rao',
    reasonKind: leaveId == null
        ? SubstitutionReasonKind.absence
        : SubstitutionReasonKind.leave,
    reason: 'Cover',
    leaveApplicationId: leaveId,
    status: status,
  );
}

void main() {
  final published = _tt('sa');
  final publishedCells = _cells(published, 'math', 't1', 'Meera Iyer');
  FakeTimetableRepository repoWithPublished() => FakeTimetableRepository(
    timetables: [published.copyWith(entryCount: publishedCells.length)],
    entries: {published.timetableId: publishedCells},
  );

  group('route and navigation permissions', () {
    testWidgets('a parent reaches only /my-timetable', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [fakeStudent('stu-1', 'Anil')],
      );
      await w.go(tester, '/my-timetable');
      expect(w.location, '/my-timetable');
      for (final p in [
        '/timetable',
        '/timetable/periods',
        '/timetable/editor/x',
        '/timetable/view',
        '/timetable/teachers',
        '/timetable/conflicts',
        '/timetable/substitutions',
        '/timetable/substitutions/new',
        '/timetable/history',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets(
      'a teacher sees their own timetable and nothing administrative',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher);
        await w.go(tester, '/my-timetable');
        expect(w.location, '/my-timetable');
        for (final p in [
          '/timetable',
          '/timetable/editor/y1__c5__sa__v1',
          '/timetable/substitutions',
          '/timetable/substitutions/new',
        ]) {
          await w.go(tester, p);
          expect(w.location, '/dashboard', reason: p);
        }
      },
    );

    testWidgets('finance has no timetable access', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      for (final p in ['/timetable', '/my-timetable']) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets('a branch admin opens every timetable screen', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        timetables: repoWithPublished(),
      );
      for (final p in [
        '/timetable',
        '/timetable/periods',
        '/timetable/view',
        '/timetable/teachers',
        '/timetable/conflicts',
        '/timetable/substitutions',
        '/timetable/substitutions/new',
        '/timetable/history',
        '/timetable/editor/${published.timetableId}',
      ]) {
        await w.go(tester, p);
        expect(w.location, p);
      }
    });
  });

  group('timetable list', () {
    testWidgets(
      'shows versions with status and effective range; filters by status',
      (tester) async {
        final draft = _tt(
          'sb',
          status: TimetableStatus.draft,
          from: '2026-09-01',
        );
        final repo = FakeTimetableRepository(
          timetables: [published, draft],
          entries: {published.timetableId: publishedCells},
        );
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          timetables: repo,
        );
        await w.go(tester, '/timetable');
        expect(find.textContaining('Class 5 SA · v1'), findsOneWidget);
        expect(find.textContaining('Class 5 SB · v1'), findsOneWidget);
        expect(find.text('Published'), findsWidgets);
        expect(find.text('Draft'), findsWidgets);
        expect(find.text('New timetable'), findsOneWidget);
      },
    );

    testWidgets('empty year says so', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/timetable');
      expect(
        find.text('No timetables yet for this academic year.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'creating a draft validates the class, section and start date',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/timetable');
        await tester.tap(find.text('New timetable'));
        await tester.pumpAndSettle();
        await tester.tap(_filled('Create draft'));
        await tester.pumpAndSettle();
        expect(find.text('Choose the class and section.'), findsOneWidget);
        expect(w.timetables.created, isEmpty);
      },
    );
  });

  group('editor', () {
    final draft = _tt(
      'sa',
      version: 2,
      status: TimetableStatus.draft,
      from: '2026-09-01',
    );

    Future<_World> openDraft(
      WidgetTester tester, {
      FakeTimetableRepository? repo,
      Size size = const Size(1400, 1000),
    }) async {
      final r =
          repo ??
          (FakeTimetableRepository(
            timetables: [published, draft],
            entries: {
              published.timetableId: publishedCells,
              draft.timetableId: const [],
            },
          ));
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        timetables: r,
        size: size,
      );
      await w.go(tester, '/timetable/editor/${draft.timetableId}');
      return w;
    }

    testWidgets('lists the day\'s slots: periods to assign, breaks as breaks', (
      tester,
    ) async {
      await openDraft(tester);
      expect(find.text('Tap to assign'), findsWidgets);
      expect(find.text('Break'), findsWidgets);
      expect(find.textContaining('Period 1 · 09:00–09:40'), findsWidgets);
    });

    testWidgets(
      'only subjects with an assigned teacher in this section are offered',
      (tester) async {
        await openDraft(tester);
        await tester.tap(find.text('Tap to assign').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        expect(find.text('Maths — Meera Iyer'), findsWidgets);
        expect(find.text('English — Nikhil Rao'), findsWidgets);
        // section sb's maths teacher (Omar) is not offered for section sa
        expect(find.textContaining('Omar'), findsNothing);
      },
    );

    testWidgets('assigning a cell and saving writes exactly that cell', (
      tester,
    ) async {
      final w = await openDraft(tester);
      await tester.tap(find.text('Tap to assign').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maths — Meera Iyer').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Room (optional)'),
        'Lab 2',
      );
      await tester.tap(find.text('Set period'));
      await tester.pumpAndSettle();
      expect(find.text('Maths'), findsWidgets);
      expect(find.textContaining('Meera Iyer · Lab 2'), findsOneWidget);

      await tester.tap(_filled('Save draft'));
      await tester.pumpAndSettle();
      expect(w.timetables.saves.single.upserts, 1);
      expect(w.timetables.saves.single.removals, 0);
      expect(find.text('Draft saved.'), findsOneWidget);
    });

    testWidgets(
      'a teacher double-booked with a published timetable is named in Validate',
      (tester) async {
        // sb (published) also has Meera in period 1 on every day
        final sb = _tt('sb');
        final repo = FakeTimetableRepository(
          timetables: [published, sb, draft],
          entries: {
            published.timetableId: publishedCells,
            sb.timetableId: _cells(sb, 'math', 't1', 'Meera Iyer'),
            draft.timetableId: _cells(draft, 'math', 't1', 'Meera Iyer')
                .where((e) => e.weekday == Weekday.monday)
                .map((e) => e.copyWith(live: false))
                .toList(),
          },
        );
        await openDraft(tester, repo: repo);
        await tester.tap(find.text('Validate'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Meera Iyer is already teaching Class 5 SB'),
          findsOneWidget,
        );
        expect(find.textContaining('problem'), findsWidgets);
      },
    );

    testWidgets(
      'PUBLISH is refused while there are errors, and nothing is published',
      (tester) async {
        final sb = _tt('sb');
        final repo = FakeTimetableRepository(
          timetables: [sb, draft.copyWith(entryCount: 1)],
          entries: {
            sb.timetableId: _cells(sb, 'math', 't1', 'Meera Iyer'),
            draft.timetableId: [
              _cells(draft, 'math', 't1', 'Meera Iyer')
                  .firstWhere((e) => e.weekday == Weekday.monday)
                  .copyWith(live: false),
            ],
          },
        );
        final w = await openDraft(tester, repo: repo);
        await tester.tap(_filled('Publish'));
        await tester.pumpAndSettle();
        expect(find.text('Publish this timetable?'), findsNothing);
        expect(w.timetables.publishes, isEmpty);
        expect(
          find.textContaining('must be fixed before publishing'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a clean draft publishes after confirmation; the replaced version is shown',
      (tester) async {
        final repo = FakeTimetableRepository(
          timetables: [
            published.copyWith(entryCount: 1),
            draft.copyWith(entryCount: 1),
          ],
          entries: {
            published.timetableId: publishedCells,
            draft.timetableId: [
              _cells(draft, 'math', 't1', 'Meera Iyer')
                  .firstWhere((e) => e.weekday == Weekday.monday)
                  .copyWith(live: false),
            ],
          },
        );
        final w = await openDraft(tester, repo: repo);
        await tester.tap(_filled('Publish'));
        await tester.pumpAndSettle();
        expect(find.text('Publish this timetable?'), findsOneWidget);
        expect(find.textContaining('v1 ends on'), findsOneWidget);
        expect(
          w.timetables.publishes,
          isEmpty,
          reason: 'nothing before confirming',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Publish').last);
        await tester.pumpAndSettle();
        expect(w.timetables.publishes, hasLength(1));
        expect(w.timetables.timetables[draft.timetableId]!.isPublished, isTrue);
        expect(find.text('Timetable published.'), findsOneWidget);
      },
    );

    testWidgets(
      'CONCURRENT PUBLISH: if another publish lands first, this one is refused and nothing changes',
      (tester) async {
        final repo = FakeTimetableRepository(
          timetables: [draft.copyWith(entryCount: 1)],
          entries: {
            draft.timetableId: [
              _cells(draft, 'math', 't1', 'Meera Iyer')
                  .firstWhere((e) => e.weekday == Weekday.monday)
                  .copyWith(live: false),
            ],
          },
        );
        final w = await openDraft(tester, repo: repo);
        await tester.tap(_filled('Publish'));
        await tester.pumpAndSettle();
        // someone else publishes while the confirmation dialog is open
        repo.lockSequence = 7;
        await tester.tap(find.widgetWithText(FilledButton, 'Publish').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Another timetable was published'),
          findsOneWidget,
        );
        expect(w.timetables.timetables[draft.timetableId]!.isDraft, isTrue);
        expect(w.timetables.lockSequence, 7);
      },
    );

    testWidgets(
      'a published version is read-only: no save, validate or publish',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          timetables: repoWithPublished(),
        );
        await w.go(tester, '/timetable/editor/${published.timetableId}');
        expect(find.textContaining('read-only'), findsOneWidget);
        expect(find.text('Save draft'), findsNothing);
        expect(find.text('Publish'), findsNothing);
        expect(find.text('Tap to assign'), findsNothing);
        expect(find.text('Withdraw'), findsOneWidget);
      },
    );

    for (final size in [
      const Size(360, 800),
      const Size(800, 1000),
      const Size(1400, 900),
    ]) {
      testWidgets('no overflow at ${size.width.toInt()}px', (tester) async {
        await openDraft(tester, size: size);
        expect(find.text('Tap to assign'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('bell schedules', () {
    testWidgets(
      'overlapping times are refused with the periods named; a valid schedule saves',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/timetable/periods');
        await tester.tap(find.text('New bell schedule'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Short Saturday',
        );
        // first slot is 09:00–09:40; add a second that overlaps it
        await tester.tap(find.text('Period').last);
        await tester.pumpAndSettle();
        final starts = find.widgetWithText(TextField, 'Start');
        await tester.enterText(starts.last, '09:30');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.textContaining('overlaps'), findsOneWidget);
        expect(w.periodSets.saved, isEmpty);

        await tester.enterText(starts.last, '09:40');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(w.periodSets.saved, hasLength(1));
        expect(w.periodSets.saved.single.teachingSlots.map((s) => s.number), [
          1,
          2,
        ]);
      },
    );

    testWidgets('malformed times are refused', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/timetable/periods');
      await tester.tap(find.text('New bell schedule'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Odd');
      await tester.enterText(
        find.widgetWithText(TextField, 'Start').first,
        '9am',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HH:MM'), findsOneWidget);
      expect(w.periodSets.saved, isEmpty);
    });
  });

  group('substitutions', () {
    Future<_World> start(
      WidgetTester tester, {
      FakeSubstitutionRepository? subs,
      FakeLeaveCalendarRepository? leave,
    }) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        timetables: repoWithPublished(),
        substitutions: subs,
        leave: leave,
      );
      return w;
    }

    Future<void> findPeriods(
      WidgetTester tester, {
      String teacher = 'Meera Iyer',
    }) async {
      await tester.tap(
        find
            .ancestor(
              of: find.text('Teacher being covered'),
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(teacher).last);
      await tester.pumpAndSettle();
      await tester.tap(_filled('Find affected periods'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'finds the teacher\'s periods; eligible people are offered, others explained',
      (tester) async {
        final w = await start(tester);
        await w.go(tester, '/timetable/substitutions/new');
        await findPeriods(tester);
        expect(find.text('1 affected period'), findsOneWidget);
        expect(find.textContaining('P1'), findsWidgets);
        // Omar teaches maths (sb) and is free; Nikhil teaches this class
        await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Omar Khan'), findsWidgets);
        expect(find.textContaining('Nikhil Rao'), findsWidgets);
        // the replaced teacher is never offered (only the selected-teacher
        // field itself shows the name)
        expect(find.textContaining('Meera Iyer'), findsOneWidget);
      },
    );

    testWidgets(
      'suggestions are not applied: nothing is assigned until the admin chooses and confirms',
      (tester) async {
        final w = await start(tester);
        await w.go(tester, '/timetable/substitutions/new');
        await findPeriods(tester);
        await tester.tap(_filled('Review and confirm'));
        await tester.pumpAndSettle();
        expect(
          find.text('Choose a substitute for at least one period.'),
          findsOneWidget,
        );
        expect(w.substitutions.assigned, isEmpty);
      },
    );

    testWidgets(
      'choose, preview, confirm: one cover is created for that date, original untouched',
      (tester) async {
        final w = await start(tester);
        await w.go(tester, '/timetable/substitutions/new');
        await findPeriods(tester);
        await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Omar Khan').last);
        await tester.pumpAndSettle();
        await tester.tap(_filled('Review and confirm'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm these covers?'), findsOneWidget);
        expect(find.textContaining('Meera Iyer → Omar Khan'), findsOneWidget);
        expect(
          w.substitutions.assigned,
          isEmpty,
          reason: 'nothing before confirming',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm 1'));
        await tester.pumpAndSettle();

        expect(w.substitutions.assigned, hasLength(1));
        final s = w.substitutions.assigned.single;
        expect(s.dateKey, _today());
        expect(s.originalTeacherId, 't1');
        expect(s.substituteTeacherId, 't3');
        expect(s.timetableId, published.timetableId);
        expect(s.slotId, 'p1');
        expect(
          w.timetables.entries[published.timetableId]!.every(
            (e) => e.teacherStaffId == 't1',
          ),
          isTrue,
          reason: 'the timetable itself is never rewritten',
        );
      },
    );

    testWidgets(
      'a teacher who is already teaching at that time is not eligible, with the reason',
      (tester) async {
        // Omar (t3) teaches section sb period 1 every day (published too)
        final sb = _tt('sb');
        final repo = FakeTimetableRepository(
          timetables: [published, sb],
          entries: {
            published.timetableId: publishedCells,
            sb.timetableId: _cells(sb, 'math', 't3', 'Omar Khan'),
          },
        );
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          timetables: repo,
        );
        await w.go(tester, '/timetable/substitutions/new');
        await findPeriods(tester);
        expect(find.text('2 not available'), findsOneWidget);
        await tester.tap(find.text('2 not available'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Teaches Class 5 SB'), findsOneWidget);
      },
    );

    testWidgets('a teacher on approved leave that day is not eligible', (
      tester,
    ) async {
      final leave = FakeLeaveCalendarRepository(
        entries: [
          LeaveCalendarEntry(
            applicationId: 'L1',
            schoolId: 'school-1',
            branchId: 'main',
            kind: LeaveKind.staff,
            subjectId: 't2',
            subjectName: 'Nikhil Rao',
            startDateKey: _today(),
            endDateKey: _today(),
            countedDateKeys: [_today()],
          ),
        ],
      );
      final w = await start(tester, leave: leave);
      await w.go(tester, '/timetable/substitutions/new');
      await findPeriods(tester);
      await tester.tap(find.textContaining('not available'));
      await tester.pumpAndSettle();
      expect(find.textContaining('approved leave'), findsWidgets);
    });

    testWidgets('an already covered period cannot be covered twice', (
      tester,
    ) async {
      final subs = FakeSubstitutionRepository(
        items: [_cover(date: _today(), substitute: 't2')],
      );
      final w = await start(tester, subs: subs);
      await w.go(tester, '/timetable/substitutions/new');
      await findPeriods(tester);
      expect(
        find.textContaining('Already covered by Nikhil Rao'),
        findsOneWidget,
      );
      expect(
        find.byType(DropdownButtonFormField<String?>),
        findsNothing,
        reason: 'a covered period offers no substitute choice',
      );
    });

    testWidgets(
      'if the date changed meanwhile, the cover is refused with a clear message',
      (tester) async {
        final subs = FakeSubstitutionRepository()
          ..error = const ConflictFailure(
            'Substitutions for this date changed.',
          );
        final w = await start(tester, subs: subs);
        await w.go(tester, '/timetable/substitutions/new');
        await findPeriods(tester);
        await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Omar Khan').last);
        await tester.pumpAndSettle();
        await tester.tap(_filled('Review and confirm'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm 1'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Substitutions for this date changed'),
          findsOneWidget,
        );
        expect(subs.assigned, isEmpty);
      },
    );

    testWidgets(
      'the list flags a cover whose leave was cancelled and one whose substitute went on leave',
      (tester) async {
        final subs = FakeSubstitutionRepository(
          items: [
            _cover(date: _today(), leaveId: 'L-gone'),
            _cover(date: _today(), t: _tt('sb'), substitute: 't3'),
          ],
        );
        final leave = FakeLeaveCalendarRepository(
          entries: [
            LeaveCalendarEntry(
              applicationId: 'L9',
              schoolId: 'school-1',
              branchId: 'main',
              kind: LeaveKind.staff,
              subjectId: 't3',
              subjectName: 'Omar',
              startDateKey: _today(),
              endDateKey: _today(),
              countedDateKeys: [_today()],
            ),
          ],
        );
        final tts = FakeTimetableRepository(
          timetables: [published, _tt('sb')],
          entries: {
            published.timetableId: publishedCells,
            _tt('sb').timetableId: _cells(
              _tt('sb'),
              'math',
              't1',
              'Meera Iyer',
            ),
          },
        );
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          timetables: tts,
          substitutions: subs,
          leave: leave,
        );
        await w.go(tester, '/timetable/substitutions');
        expect(find.textContaining('no longer approved'), findsOneWidget);
        expect(find.textContaining('now has approved leave'), findsOneWidget);
      },
    );

    testWidgets('cancelling a cover needs a reason and records it', (
      tester,
    ) async {
      final subs = FakeSubstitutionRepository(items: [_cover(date: _today())]);
      final w = await start(tester, subs: subs);
      await w.go(tester, '/timetable/substitutions');
      await tester.tap(find.text('Cancel cover').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel cover'));
      await tester.pumpAndSettle();
      expect(subs.cancelled, isEmpty, reason: 'a reason is required');
      await tester.enterText(find.byType(TextField).last, 'Teacher is back');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel cover'));
      await tester.pumpAndSettle();
      expect(subs.cancelled.single.reason, 'Teacher is back');
      expect(find.text('Cover cancelled.'), findsOneWidget);
    });

    testWidgets('an empty period says so', (tester) async {
      final w = await start(tester);
      await w.go(tester, '/timetable/substitutions');
      expect(find.text('No substitutions in this period.'), findsOneWidget);
    });
  });

  group('teacher and parent views', () {
    testWidgets('a teacher sees their periods, covers and who covers theirs', (
      tester,
    ) async {
      final subs = FakeSubstitutionRepository(
        items: [_cover(date: _today(), substitute: 't2')],
      );
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        timetables: repoWithPublished(),
        substitutions: subs,
      );
      await w.go(tester, '/my-timetable');
      expect(find.text('Meera Iyer'), findsOneWidget);
      expect(find.textContaining('Maths · Class 5 SA'), findsWidgets);
      expect(find.textContaining('Covered by Nikhil Rao'), findsOneWidget);
      // no editing affordances at all
      expect(find.text('Tap to assign'), findsNothing);
      expect(find.text('Arrange cover'), findsNothing);
    });

    testWidgets('a teacher without a staff record is told why', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher);
      await w.go(tester, '/my-timetable');
      expect(
        find.textContaining("isn't linked to a staff record"),
        findsOneWidget,
      );
    });

    testWidgets(
      'a parent sees the linked child\'s section with substitute and no staff-only details',
      (tester) async {
        final sa = Student(
          studentId: 'stu-1',
          schoolId: 'school-1',
          branchId: 'main',
          admissionNumber: 'ADM-1',
          studentCode: 'STU-1',
          firstName: 'Anil',
          lastName: 'Kumar',
          dateOfBirth: DateTime(2015, 4, 10),
          gender: Gender.male,
          admissionDate: DateTime(2026, 6, 1),
          status: StudentStatus.active,
          currentAcademicYearId: 'y1',
          currentClassId: 'c5',
          currentSectionId: 'sa',
        );
        final subs = FakeSubstitutionRepository(
          items: [_cover(date: _today())],
        );
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'p1',
          children: [sa],
          timetables: repoWithPublished(),
          substitutions: subs,
        );
        await w.go(tester, '/my-timetable');
        expect(find.textContaining('Maths'), findsWidgets);
        expect(
          find.textContaining('Substitute for Meera Iyer'),
          findsOneWidget,
        );
        expect(find.text('Save draft'), findsNothing);
        expect(find.text('Publish'), findsNothing);
      },
    );

    testWidgets(
      'a parent with no children or no placement gets a clear message',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'p1',
          children: [fakeStudent('stu-1', 'Anil')],
        );
        await w.go(tester, '/my-timetable');
        expect(
          find.textContaining('not been placed in a class'),
          findsOneWidget,
        );
      },
    );

    for (final size in [const Size(360, 800), const Size(1400, 900)]) {
      testWidgets('my timetable has no overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          ownStaffId: 't1',
          timetables: repoWithPublished(),
          size: size,
        );
        await w.go(tester, '/my-timetable');
        expect(find.textContaining('Maths'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('conflict report and history', () {
    testWidgets('lists findings per timetable; clean state says so', (
      tester,
    ) async {
      final sb = _tt('sb');
      final dirty = FakeTimetableRepository(
        timetables: [published, sb],
        entries: {
          published.timetableId: publishedCells,
          sb.timetableId: _cells(sb, 'math', 't1', 'Meera Iyer'),
        },
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        timetables: dirty,
      );
      await w.go(tester, '/timetable/conflicts');
      expect(find.textContaining('have findings'), findsOneWidget);
      expect(find.textContaining('is already teaching'), findsWidgets);
    });

    testWidgets('an empty year has nothing to check', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/timetable/conflicts');
      expect(
        find.text('No draft or published timetables to check.'),
        findsOneWidget,
      );
    });

    testWidgets('history empty state', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/timetable/history');
      expect(
        find.text('No timetable activity yet for this year.'),
        findsOneWidget,
      );
    });
  });
}
