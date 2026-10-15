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
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_settings_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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
import 'package:eazy_school_360/features/timetable/presentation/providers/timetable_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_registers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance_repository.dart';
import 'package:eazy_school_360/features/attendance/presentation/providers/attendance_providers.dart';
import 'package:eazy_school_360/features/exams/domain/exam_enums.dart';
import 'package:eazy_school_360/features/exams/domain/examination.dart';
import 'package:eazy_school_360/features/exams/domain/grading_scheme.dart';
import 'package:eazy_school_360/features/exams/domain/marks.dart';
import 'package:eazy_school_360/features/exams/presentation/providers/exam_providers.dart';
import 'package:eazy_school_360/features/exams/domain/exam_repositories.dart';
import 'package:eazy_school_360/features/exams/domain/result_calculator.dart';
import 'package:eazy_school_360/features/exams/domain/result_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/exam_fakes.dart';
import '../support/fakes.dart';
import '../support/homework_fakes.dart' show FakeStudentRepository;
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
    String? branchId,
  }) async => children;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TeacherAssignment _assign(
  String teacher,
  String section,
  String subject, {
  bool classTeacher = false,
}) => TeacherAssignment(
  assignmentId: 'a-$teacher-$section-$subject',
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  teacherStaffId: teacher,
  classId: 'c5',
  sectionId: section,
  subjectId: classTeacher ? null : subject,
  isClassTeacher: classTeacher,
  startDate: DateTime(2026, 6, 1),
  status: TeacherAssignmentStatus.active,
);

Student _student(
  String id,
  String first, {
  String section = 'sa',
  String? roll,
  StudentStatus status = StudentStatus.active,
}) => Student(
  studentId: id,
  schoolId: 'school-1',
  branchId: 'main',
  admissionNumber: 'ADM-$id',
  studentCode: 'STU-$id',
  firstName: first,
  lastName: 'Kumar',
  dateOfBirth: DateTime(2015, 4, 10),
  gender: Gender.male,
  admissionDate: DateTime(2026, 6, 1),
  status: status,
  currentAcademicYearId: 'y1',
  currentClassId: 'c5',
  currentSectionId: section,
  currentRollNumber: roll,
);

/// Returns canned attendance for any student: 8 present, 2 absent.
class _FakeAttendance implements StudentAttendanceRepository {
  @override
  Future<AttendanceRange<StudentAttendance>> fetchStudentRange({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String fromKey,
    required String toKey,
  }) async => AttendanceRange([
    for (var i = 0; i < 10; i++)
      StudentAttendance(
        attendanceId: 'a$i',
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: 'y1',
        dateKey: '2026-08-${(i + 1).toString().padLeft(2, '0')}',
        studentId: studentId,
        academicRecordId: 'r',
        classId: 'c5',
        sectionId: 'sa',
        status: i < 8 ? AttendanceStatus.present : AttendanceStatus.absent,
        revision: 1,
      ),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GradingScheme _scheme({String id = 'gs1', bool ranking = false}) =>
    GradingScheme(
      schemeId: id,
      schoolId: 'school-1',
      branchId: 'main',
      name: 'Standard',
      bands: const [
        GradeBand(grade: 'A', minPercent: 80),
        GradeBand(grade: 'B', minPercent: 60),
        GradeBand(grade: 'C', minPercent: 33),
        GradeBand(grade: 'D', minPercent: 0),
      ],
      rankingEnabled: ranking,
    );

Examination _exam({
  ExamStatus status = ExamStatus.draft,
  String name = 'Half-yearly',
  String? section = 'sa',
  int subjects = 0,
  int sheets = 0,
  int approved = 0,
  int version = 0,
  int count = 0,
  int written = 0,
  String schemeId = 'gs1',
}) => Examination(
  examId: Examination.idFor(
    academicYearId: 'y1',
    classId: 'c5',
    sectionId: section,
    name: name,
  ),
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: section,
  classLabel: section == null
      ? 'Class 5'
      : 'Class 5 – ${section.toUpperCase()}',
  name: name,
  type: ExamType.halfYearly,
  schemeId: schemeId,
  startDateKey: '2026-09-01',
  endDateKey: '2026-09-10',
  status: status,
  subjectCount: subjects,
  sheetCount: sheets,
  approvedSheets: approved,
  resultVersion: version,
  resultCount: count,
  resultsWritten: written,
  schemeSnapshot: version > 0 ? _scheme(id: schemeId).policyMap() : null,
);

ExaminationSubject _subject(
  Examination e,
  String id,
  String name, {
  double max = 100,
  double? pass,
  double? theory,
  double? practical,
}) => ExaminationSubject(
  examId: e.examId,
  subjectId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  subjectName: name,
  maxMarks: max,
  passMarks: pass,
  theoryMax: theory,
  practicalMax: practical,
);

MarksEntry _mark(
  Examination e,
  String subject,
  String student,
  MarkStatus status, {
  double? marks,
  String section = 'sa',
}) => MarksEntry(
  sheetId: MarksSheet.idFor(e.examId, subject, section),
  examId: e.examId,
  subjectId: subject,
  studentId: student,
  studentName: student == 's1' ? 'Anil Kumar' : 'Bela Kumar',
  classId: 'c5',
  sectionId: section,
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  status: status,
  marks: marks,
  revision: 1,
);

class _World {
  final ProviderContainer container;
  final FakeExamRepository exams;
  final FakeMarksRepository marks;
  final FakeResultRepository results;
  final FakeGradingSchemeRepository schemes;

  _World(this.container, this.exams, this.marks, this.results, this.schemes);

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
  FakeExamRepository? exams,
  FakeGradingSchemeRepository? schemes,
  void Function(FakeMarksRepository marks)? seedMarks,
  void Function(FakeResultRepository results)? seedResults,
  List<TeacherAssignment>? assignments,
  List<Student>? roster,
  List<Student> children = const [],
  String? linkedParentId,
  String? ownStaffId,
  Size size = const Size(1400, 1000),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final ex = exams ?? FakeExamRepository();
  final sc = schemes ?? FakeGradingSchemeRepository(schemes: [_scheme()]);
  final marks = FakeMarksRepository(ex);
  final results = FakeResultRepository(ex);
  seedMarks?.call(marks);
  seedResults?.call(results);
  final teacherAssignments = FakeTeacherAssignmentRepository()
    ..existing =
        assignments ??
        [_assign('t1', 'sa', 'math'), _assign('t2', 'sa', 'sci')];

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
            for (final (id, name) in [
              ('math', 'Maths'),
              ('sci', 'Science'),
              ('eng', 'English'),
            ])
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
          classSubjectIds: const {
            'c5': ['math', 'sci', 'eng'],
          },
        ),
      ),
      academicSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      calendarRepositoryProvider.overrideWithValue(
        FakeCalendarRepository(workingDays: null),
      ),
      parentRepositoryProvider.overrideWithValue(
        _FakeParentRepository(children),
      ),
      studentRepositoryProvider.overrideWithValue(
        FakeStudentRepository(
          roster ??
              [
                _student('s1', 'Anil', roll: '1'),
                _student('s2', 'Bela', roll: '2'),
              ],
        ),
      ),
      studentAttendanceRepositoryProvider.overrideWithValue(_FakeAttendance()),
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
              userId: ownStaffId == 't2' ? _uid : 'u-t2',
            ),
          ],
        ),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(teacherAssignments),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
      leaveNotificationRepositoryProvider.overrideWithValue(
        FakeLeaveNotificationRepository(),
      ),
      gradingSchemeRepositoryProvider.overrideWithValue(sc),
      examRepositoryProvider.overrideWithValue(ex),
      marksRepositoryProvider.overrideWithValue(marks),
      resultRepositoryProvider.overrideWithValue(results),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, ex, marks, results, sc);
}

/// Taps a control, scrolling the page to it first.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

Finder _btn(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is FilledButton || w is OutlinedButton || w is TextButton,
      ),
    )
    .first;

/// An examination ready to finalise: marks in, sheets approved.
({FakeExamRepository exams, Examination exam}) _ready() {
  final e = _exam(
    status: ExamStatus.inProgress,
    subjects: 2,
    sheets: 2,
    approved: 2,
  );
  final repo = FakeExamRepository(
    exams: [e],
    subjects: [
      _subject(e, 'math', 'Maths'),
      _subject(e, 'sci', 'Science', max: 50),
    ],
  );
  return (exams: repo, exam: e);
}

void _seedReady(FakeMarksRepository m, Examination e) {
  m.seed(e, 'math', 'sa', [
    _mark(e, 'math', 's1', MarkStatus.entered, marks: 80),
    _mark(e, 'math', 's2', MarkStatus.entered, marks: 30),
  ]);
  m.seed(e, 'sci', 'sa', [
    _mark(e, 'sci', 's1', MarkStatus.entered, marks: 40),
    _mark(e, 'sci', 's2', MarkStatus.absent),
  ]);
}

void main() {
  group('route and navigation permissions', () {
    testWidgets('a parent reaches only /my-results', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_student('s1', 'Anil')],
      );
      await w.go(tester, '/my-results');
      expect(w.location, '/my-results');
      for (final p in [
        '/exams',
        '/exams/new',
        '/exams/schemes',
        '/exams/performance',
        '/exams/detail/x',
        '/exams/marks/x/math/sa',
        '/exams/review/x',
        '/exams/results/x',
        '/exams/results/x/s1',
        '/exams/history/x',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets(
      'a teacher enters marks and views; cannot configure or approve',
      (tester) async {
        final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
        for (final p in ['/exams', '/exams/performance', '/exams/detail/x']) {
          await w.go(tester, p);
          expect(w.location, p);
        }
        for (final p in [
          '/exams/new',
          '/exams/schemes',
          '/exams/edit/x',
          '/exams/review/x',
          '/exams/results/x',
          '/exams/results/x/s1',
          '/exams/history/x',
          '/my-results',
        ]) {
          await w.go(tester, p);
          expect(w.location, '/dashboard', reason: p);
        }
      },
    );

    testWidgets('finance has no examination access', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      for (final p in ['/exams', '/my-results', '/exams/performance']) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets('a branch admin opens every examination screen', (
      tester,
    ) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      for (final p in [
        '/exams',
        '/exams/new',
        '/exams/schemes',
        '/exams/performance',
        '/exams/detail/${r.exam.examId}',
        '/exams/review/${r.exam.examId}',
        '/exams/results/${r.exam.examId}',
        '/exams/results/${r.exam.examId}/s1',
        '/exams/history/${r.exam.examId}',
      ]) {
        await w.go(tester, p);
        expect(w.location, p);
        expect(tester.takeException(), isNull, reason: p);
      }
    });
  });

  group('examination list and configuration', () {
    testWidgets('lists examinations with their state; teachers cannot create', (
      tester,
    ) async {
      final repo = FakeExamRepository(
        exams: [
          _exam(),
          _exam(
            name: 'Unit test 1',
            status: ExamStatus.published,
            version: 1,
            count: 2,
            written: 2,
          ),
        ],
      );
      final admin = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: repo,
      );
      await admin.go(tester, '/exams');
      expect(find.text('Half-yearly'), findsWidgets);
      expect(find.text('Unit test 1'), findsWidgets);
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('Published'), findsWidgets);
      expect(find.text('New examination'), findsOneWidget);
    });

    testWidgets('teacher list has no create action', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: FakeExamRepository(exams: [_exam()]),
      );
      await w.go(tester, '/exams');
      expect(find.text('New examination'), findsNothing);
      expect(find.text('Half-yearly'), findsWidgets);
    });

    testWidgets('empty state', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/exams');
      expect(find.textContaining('No examinations match'), findsOneWidget);
    });

    testWidgets('creating validates, then creates; a duplicate is refused', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/exams/new');
      await _tap(tester, find.text('Create examination'));
      expect(
        find.textContaining('Enter at least 3 characters'),
        findsOneWidget,
      );
      expect(w.exams.exams, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Half-yearly',
      );
      await tester.tap(find.text('Class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 5').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Create examination'));
      expect(
        find.textContaining('Choose the start and end dates'),
        findsOneWidget,
      );

      await _tap(tester, find.text('Start date'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('End date'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Create examination'));
      expect(w.exams.exams.length, 1);
      final e = w.exams.exams.values.single;
      expect(e.name, 'Half-yearly');
      expect(e.classId, 'c5');
      expect(e.sectionId, isNull);
      expect(e.status, ExamStatus.draft);
      expect(e.examId, 'y1__c5__ALL__half-yearly');
    });

    testWidgets('a finalised examination cannot be edited', (tester) async {
      final e = _exam(
        status: ExamStatus.published,
        version: 1,
        count: 2,
        written: 2,
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: FakeExamRepository(exams: [e]),
      );
      await w.go(tester, '/exams/edit/${e.examId}');
      expect(find.textContaining('Only a draft or scheduled'), findsOneWidget);
    });
  });

  group('subjects and workflow', () {
    testWidgets('subject marks are validated; pass above max is refused', (
      tester,
    ) async {
      final e = _exam();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: FakeExamRepository(exams: [e]),
      );
      await w.go(tester, '/exams/detail/${e.examId}');
      await _tap(tester, find.text('Add subject'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maths').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Passing marks (blank = scheme percentage)',
        ),
        '150',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Passing marks must be between'),
        findsOneWidget,
      );
      expect(w.exams.subjects[e.examId] ?? {}, isEmpty);

      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Passing marks (blank = scheme percentage)',
        ),
        '35',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(w.exams.subjects[e.examId]!.keys, ['math']);
      expect(w.exams.exams[e.examId]!.subjectCount, 1);
    });

    testWidgets('scheduling needs at least one subject', (tester) async {
      final e = _exam();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: FakeExamRepository(exams: [e]),
      );
      await w.go(tester, '/exams/detail/${e.examId}');
      await _tap(tester, find.text('Schedule'));
      expect(w.exams.exams[e.examId]!.status, ExamStatus.draft);
    });

    testWidgets('opening marks entry needs a confirmation', (tester) async {
      final s = _exam(status: ExamStatus.scheduled, subjects: 2);
      final repo = FakeExamRepository(
        exams: [s],
        subjects: [_subject(s, 'math', 'Maths'), _subject(s, 'sci', 'Science')],
      );
      final w = await _pump(tester, role: UserRole.branchAdmin, exams: repo);
      await w.go(tester, '/exams/detail/${s.examId}');
      await _tap(tester, find.text('Open marks entry'));
      expect(find.text('Open marks entry?'), findsOneWidget);
      expect(find.textContaining('2 marks sheet(s)'), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.exams[s.examId]!.status, ExamStatus.scheduled);
      await _tap(tester, find.text('Open marks entry'));
      await tester.tap(_inDialog('Open marks entry'));
      await tester.pumpAndSettle();
      expect(repo.exams[s.examId]!.status, ExamStatus.inProgress);
      expect(repo.exams[s.examId]!.sheetCount, 2);
    });

    testWidgets('cancelling needs a reason and is recorded', (tester) async {
      final e = _exam();
      final repo = FakeExamRepository(exams: [e]);
      final w = await _pump(tester, role: UserRole.branchAdmin, exams: repo);
      await w.go(tester, '/exams/detail/${e.examId}');
      await _tap(tester, find.text('Cancel'));
      await tester.tap(_inDialog('Cancel examination'));
      await tester.pumpAndSettle();
      expect(repo.exams[e.examId]!.status, ExamStatus.draft);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Held next term',
      );
      await tester.tap(_inDialog('Cancel examination'));
      await tester.pumpAndSettle();
      expect(repo.exams[e.examId]!.status, ExamStatus.cancelled);
      expect(repo.audit.last.note, 'Held next term');
    });
  });

  group('grading schemes', () {
    testWidgets('overlapping boundaries are reported and cannot be saved', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        schemes: FakeGradingSchemeRepository(),
      );
      await w.go(tester, '/exams/schemes');
      expect(find.textContaining('No grading scheme yet'), findsOneWidget);
      await _tap(tester, find.text('New grading scheme'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My scheme',
      );
      await tester.pumpAndSettle();
      // make two grades start at the same percentage
      final fromFields = find.widgetWithText(TextField, 'From %');
      await tester.enterText(fromFields.at(1), '90');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save scheme'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('overlap'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save scheme'),
      );
      expect(save.onPressed, isNull);
      expect(w.schemes.saved, isEmpty);
    });

    testWidgets('a valid scheme is saved', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        schemes: FakeGradingSchemeRepository(),
      );
      await w.go(tester, '/exams/schemes');
      await _tap(tester, find.text('New grading scheme'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My scheme',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(FilledButton, 'Save scheme'));
      expect(w.schemes.saved.length, 1);
      expect(w.schemes.saved.single.name, 'My scheme');
      await tester.pumpAndSettle();
      expect(find.text('My scheme'), findsOneWidget);
    });
  });

  group('marks entry', () {
    ({FakeExamRepository exams, Examination exam}) open() {
      final e = _exam(status: ExamStatus.inProgress, subjects: 2, sheets: 2);
      return (
        exams: FakeExamRepository(
          exams: [e],
          subjects: [
            _subject(e, 'math', 'Maths'),
            _subject(e, 'sci', 'Science', max: 50),
          ],
        ),
        exam: e,
      );
    }

    testWidgets('a teacher sees only their own sheets', (tester) async {
      final o = open();
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: o.exams,
      );
      await w.go(tester, '/exams/detail/${o.exam.examId}');
      expect(find.text('Your marks sheets'), findsOneWidget);
      expect(find.textContaining('Maths — SA'), findsOneWidget);
      expect(find.textContaining('Science — SA'), findsNothing);
    });

    testWidgets('values above the maximum are refused; zero is a score', (
      tester,
    ) async {
      final o = open();
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: o.exams,
      );
      await w.go(tester, '/exams/marks/${o.exam.examId}/math/sa');
      expect(find.textContaining('Anil Kumar'), findsOneWidget);
      // Anil: entered, marks 150
      await tester.tap(find.byType(DropdownButton<MarkStatus>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entered').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Marks /100').first,
        '150',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot exceed 100'), findsWidgets);
      await _tap(tester, _btn('Save draft (1)'));
      expect(w.marks.entries, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Marks /100').first,
        '0',
      );
      await tester.pumpAndSettle();
      await _tap(tester, _btn('Save draft (1)'));
      final saved = w.marks.entries.values.single;
      expect(saved.status, MarkStatus.entered);
      expect(saved.marks, 0);
    });

    testWidgets(
      'absent and exempted carry no marks; pending blocks submission',
      (tester) async {
        final o = open();
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          ownStaffId: 't1',
          exams: o.exams,
        );
        await w.go(tester, '/exams/marks/${o.exam.examId}/math/sa');
        await _tap(tester, _btn('Submit for review'));
        expect(
          find.textContaining('have no marks, absence or exemption yet'),
          findsOneWidget,
        );
        expect(w.marks.submits, isEmpty);

        final dropdowns = find.byType(DropdownButton<MarkStatus>);
        await tester.tap(dropdowns.at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Absent').last);
        await tester.pumpAndSettle();
        await tester.tap(dropdowns.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Exempted').last);
        await tester.pumpAndSettle();
        await _tap(tester, _btn('Submit for review'));
        expect(find.text('Submit for review?'), findsOneWidget);
        await tester.tap(_inDialog('Submit'));
        await tester.pumpAndSettle();
        expect(w.marks.submits.length, 1);
        final entries = w.marks.entries.values.toList()
          ..sort((a, b) => a.studentId.compareTo(b.studentId));
        expect(entries.map((e) => e.status), [
          MarkStatus.absent,
          MarkStatus.exempted,
        ]);
        expect(entries.every((e) => e.marks == null), isTrue);
      },
    );

    testWidgets('a submitted sheet is read-only', (tester) async {
      final o = open();
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: o.exams,
        seedMarks: (m) => m.seed(
          o.exam,
          'math',
          'sa',
          [_mark(o.exam, 'math', 's1', MarkStatus.entered, marks: 50)],
          status: SheetStatus.submitted,
          submittedBy: 'uid-1',
        ),
      );
      await w.go(tester, '/exams/marks/${o.exam.examId}/math/sa');
      expect(find.textContaining('read-only'), findsOneWidget);
      expect(find.text('Submit for review'), findsNothing);
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Marks /100').first,
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('search narrows a long list', (tester) async {
      final o = open();
      final roster = [
        for (var i = 1; i <= 12; i++)
          _student('s$i', i == 7 ? 'Zoya' : 'Pupil$i', roll: '$i'),
      ];
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: o.exams,
        roster: roster,
      );
      await w.go(tester, '/exams/marks/${o.exam.examId}/math/sa');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search name or roll number'),
        'zoya',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Zoya'), findsOneWidget);
      expect(find.textContaining('Pupil3'), findsNothing);
    });

    testWidgets('marks components are entered separately', (tester) async {
      final e = _exam(status: ExamStatus.inProgress, subjects: 1, sheets: 1);
      final repo = FakeExamRepository(
        exams: [e],
        subjects: [_subject(e, 'sci', 'Science', theory: 70, practical: 30)],
      );
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't2',
        exams: repo,
      );
      await w.go(tester, '/exams/marks/${e.examId}/sci/sa');
      await tester.tap(find.byType(DropdownButton<MarkStatus>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entered').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Theory /70').first,
        '60',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Practical /30').first,
        '25',
      );
      await tester.pumpAndSettle();
      await _tap(tester, _btn('Save draft (1)'));
      expect(w.marks.entries.values.single.marks, 85);
    });

    testWidgets('phone layout has no overflow', (tester) async {
      final o = open();
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        exams: o.exams,
        size: const Size(390, 800),
      );
      await w.go(tester, '/exams/marks/${o.exam.examId}/math/sa');
      expect(find.textContaining('Anil Kumar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('review and approval', () {
    testWidgets('an administrator approves; the counter moves', (tester) async {
      final e = _exam(status: ExamStatus.inProgress, subjects: 1, sheets: 1);
      final repo = FakeExamRepository(
        exams: [e],
        subjects: [_subject(e, 'math', 'Maths')],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: repo,
        seedMarks: (m) => m.seed(
          e,
          'math',
          'sa',
          [_mark(e, 'math', 's1', MarkStatus.entered, marks: 50)],
          status: SheetStatus.submitted,
          submittedBy: 'someone-else',
        ),
      );
      await w.go(tester, '/exams/review/${e.examId}');
      expect(find.text('Awaiting review'), findsOneWidget);
      await _tap(tester, _btn('Approve'));
      await tester.tap(_inDialog('Approve'));
      await tester.pumpAndSettle();
      expect(w.marks.approvals.length, 1);
      expect(repo.exams[e.examId]!.approvedSheets, 1);
    });

    testWidgets('the submitter cannot approve their own sheet', (tester) async {
      final e = _exam(status: ExamStatus.inProgress, subjects: 1, sheets: 1);
      final repo = FakeExamRepository(
        exams: [e],
        subjects: [_subject(e, 'math', 'Maths')],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: repo,
        seedMarks: (m) => m.seed(
          e,
          'math',
          'sa',
          [_mark(e, 'math', 's1', MarkStatus.entered, marks: 50)],
          status: SheetStatus.submitted,
          submittedBy: _uid,
        ),
      );
      await w.go(tester, '/exams/review/${e.examId}');
      await _tap(tester, _btn('Approve'));
      await tester.tap(_inDialog('Approve'));
      await tester.pumpAndSettle();
      expect(w.marks.approvals, isEmpty);
      expect(find.textContaining('someone else must approve'), findsOneWidget);
    });

    testWidgets('returning needs a note and undoes an approval', (
      tester,
    ) async {
      final e = _exam(
        status: ExamStatus.inProgress,
        subjects: 1,
        sheets: 1,
        approved: 1,
      );
      final repo = FakeExamRepository(
        exams: [e],
        subjects: [_subject(e, 'math', 'Maths')],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: repo,
        seedMarks: (m) => m.seed(e, 'math', 'sa', [
          _mark(e, 'math', 's1', MarkStatus.entered, marks: 50),
        ]),
      );
      await w.go(tester, '/exams/review/${e.examId}');
      await _tap(tester, _btn('Return'));
      await tester.tap(_inDialog('Return'));
      await tester.pumpAndSettle();
      expect(w.marks.returns, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Check Q4',
      );
      await tester.tap(_inDialog('Return'));
      await tester.pumpAndSettle();
      expect(w.marks.returns.length, 1);
      expect(repo.exams[e.examId]!.approvedSheets, 0);
    });
  });

  group('results: calculation, finalisation, publication', () {
    testWidgets('the preview is provisional and shows incomplete students', (
      tester,
    ) async {
      final e = _exam(
        status: ExamStatus.inProgress,
        subjects: 1,
        sheets: 1,
        approved: 1,
      );
      final repo = FakeExamRepository(
        exams: [e],
        subjects: [_subject(e, 'math', 'Maths')],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: repo,
        seedMarks: (m) => m.seed(e, 'math', 'sa', [
          _mark(e, 'math', 's1', MarkStatus.entered, marks: 90),
        ]),
      );
      await w.go(tester, '/exams/results/${e.examId}');
      expect(find.text('Provisional'), findsOneWidget);
      expect(find.textContaining('Missing: 1 subject'), findsOneWidget);
      expect(find.textContaining('cannot be finalised until'), findsOneWidget);
      await _tap(tester, _btn('Finalise results'));
      expect(find.text('Finalise these results?'), findsNothing);
      expect(find.textContaining('still have missing marks'), findsOneWidget);
      expect(w.results.finalizedVersions, isEmpty);
    });

    testWidgets('finalise with confirmation, then publish with confirmation', (
      tester,
    ) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      await w.go(tester, '/exams/results/${r.exam.examId}');
      expect(find.textContaining('Anil Kumar'), findsOneWidget);
      // s1: 120/150 = 80% → A, pass; s2: 30/100 (sci absent excluded) fails maths
      await _tap(tester, _btn('Finalise results'));
      expect(find.text('Finalise these results?'), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(w.results.finalizedVersions, isEmpty);
      await _tap(tester, _btn('Finalise results'));
      await tester.tap(_inDialog('Finalise'));
      await tester.pumpAndSettle();
      expect(w.results.finalizedVersions, [1]);
      final e = r.exams.exams[r.exam.examId]!;
      expect(e.status, ExamStatus.completed);
      expect(e.resultCount, 2);
      final s1 = w.results.results['${e.examId}__s1__v1']!;
      expect(s1.result.overallGrade, 'A');
      expect(s1.result.percentage, 80);
      // the stored result carries the scheme and an attendance snapshot
      expect(s1.schemeSnapshot['name'], 'Standard');
      expect(s1.attendance!.percentage, 80);
      final s2 = w.results.results['${e.examId}__s2__v1']!;
      expect(s2.result.hasAbsence, isTrue);
      expect(s2.result.lines.last.outcome.wireValue, 'ABSENT');

      await _tap(tester, _btn('Publish results'));
      expect(find.text('Publish these results?'), findsOneWidget);
      await tester.tap(_inDialog('Publish'));
      await tester.pumpAndSettle();
      expect(w.results.published, ['${e.examId}:v1']);
      expect(r.exams.exams[e.examId]!.status, ExamStatus.published);
    });

    testWidgets('a student\'s report card shows totals, grade and remarks', (
      tester,
    ) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      await w.go(tester, '/exams/results/${r.exam.examId}/s1');
      expect(find.text('Report card'), findsOneWidget);
      expect(find.textContaining('Provisional'), findsWidgets);
      // The school name is on the report card and, as the tenant's branding,
      // in the shell's app bar: exactly one of each.
      expect(find.text('Rosewood High'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Rosewood High'),
        ),
        findsOneWidget,
      );
      expect(find.text('120 / 150'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
    });

    testWidgets('withdrawing a published result needs a reason', (
      tester,
    ) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      r.exams.put(
        r.exams.copyOf(
          r.exam,
          status: ExamStatus.published,
          resultVersion: 1,
          resultCount: 2,
          resultsWritten: 2,
        ),
      );
      await w.go(tester, '/exams/detail/${r.exam.examId}');
      await _tap(tester, _btn('Withdraw'));
      await tester.tap(_inDialog('Withdraw'));
      await tester.pumpAndSettle();
      expect(r.exams.exams[r.exam.examId]!.status, ExamStatus.published);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Marks misread',
      );
      await tester.tap(_inDialog('Withdraw'));
      await tester.pumpAndSettle();
      expect(r.exams.exams[r.exam.examId]!.status, ExamStatus.withdrawn);
      expect(r.exams.audit.last.note, 'Marks misread');
      // and it can be reopened with a reason, creating a new version later
      await _tap(tester, _btn('Reopen for correction'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Fix maths',
      );
      await tester.tap(_inDialog('Reopen'));
      await tester.pumpAndSettle();
      expect(r.exams.exams[r.exam.examId]!.status, ExamStatus.inProgress);
    });

    testWidgets('history lists each change with its reason', (tester) async {
      final e = _exam();
      final repo = FakeExamRepository(exams: [e]);
      final w = await _pump(tester, role: UserRole.branchAdmin, exams: repo);
      await repo.cancel(
        e,
        reason: 'Held next term',
        actor: const ExamActorForTest().actor,
      );
      await w.go(tester, '/exams/history/${e.examId}');
      expect(find.textContaining('cancelled'), findsWidgets);
      expect(find.textContaining('Held next term'), findsOneWidget);
    });
  });

  group('family view', () {
    Future<_World> published(
      WidgetTester tester, {
      List<Student>? children,
      bool withdraw = false,
    }) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: children ?? [_student('s1', 'Anil')],
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      // finalise + publish through the fakes
      final scheme = _scheme();
      final subjects = r.exams.subjects[r.exam.examId]!.values.toList();
      final results = [
        for (final s in ['s1', 's2'])
          ResultCalculator.calculate(
            scheme: scheme,
            subjects: subjects,
            entries: {
              for (final sub in subjects)
                sub.subjectId: w
                    .marks
                    .entries['${MarksSheet.idFor(r.exam.examId, sub.subjectId, 'sa')}__$s'],
            },
            studentId: s,
            studentName: s == 's1' ? 'Anil Kumar' : 'Bela Kumar',
            sectionId: 'sa',
          ),
      ];
      await w.results.finalize(
        exam: r.exam,
        scheme: scheme,
        results: results,
        attendance: const {},
        remarks: {
          's1': const ExamRemark(studentId: 's1', teacherRemark: 'Keep it up'),
        },
        classLabels: const {'sa': 'Class 5 – A'},
        actor: const ExamActor(userId: 'a', name: 'A', role: 'SCHOOL_ADMIN'),
      );
      await w.results.publish(
        r.exams.exams[r.exam.examId]!,
        actor: const ExamActor(userId: 'a', name: 'A', role: 'SCHOOL_ADMIN'),
      );
      if (withdraw) {
        await r.exams.withdraw(
          r.exams.exams[r.exam.examId]!,
          reason: 'Marks misread',
          actor: const ExamActor(userId: 'a', name: 'A', role: 'SCHOOL_ADMIN'),
        );
      }
      return w;
    }

    testWidgets(
      'a parent sees their child\'s published result and report card',
      (tester) async {
        final w = await published(tester);
        await w.go(tester, '/my-results');
        expect(find.text('Half-yearly'), findsOneWidget);
        expect(find.text('80%'), findsOneWidget);
        expect(find.text('Grade A'), findsOneWidget);
        await tester.tap(find.text('Half-yearly'));
        await tester.pumpAndSettle();
        expect(find.text('Report card'), findsOneWidget);
        expect(find.text('Class teacher: Keep it up'), findsOneWidget);
        expect(
          find.text('Anil Kumar · Adm. ADM-s1 · Class 5 – SA'),
          findsNothing,
        );
        expect(find.text('Print'), findsOneWidget);
        expect(find.text('Download PDF'), findsOneWidget);
      },
    );

    testWidgets('unpublished results are not shown', (tester) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_student('s1', 'Anil')],
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      await w.go(tester, '/my-results');
      expect(
        find.textContaining('No results have been published'),
        findsOneWidget,
      );
      await w.go(tester, '/my-results/${r.exam.examId}/s1');
      expect(find.text('This result is not available.'), findsOneWidget);
    });

    testWidgets('a withdrawn result disappears for the family', (tester) async {
      final w = await published(tester, withdraw: true);
      await w.go(tester, '/my-results');
      expect(
        find.textContaining('No results have been published'),
        findsOneWidget,
      );
    });

    testWidgets('another child\'s result cannot be opened by id', (
      tester,
    ) async {
      final w = await published(tester);
      final examId = w.exams.exams.keys.single;
      await w.go(tester, '/my-results/$examId/s2');
      expect(
        find.text('This child is not linked to your account.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a child in another section does not see the section\'s examination',
      (tester) async {
        final w = await published(
          tester,
          children: [_student('s3', 'Chitra', section: 'sb')],
        );
        await w.go(tester, '/my-results');
        expect(find.text('Half-yearly'), findsNothing);
      },
    );

    testWidgets('a withdrawn pupil has no current results', (tester) async {
      final w = await published(
        tester,
        children: [_student('s1', 'Anil', status: StudentStatus.left)],
      );
      await w.go(tester, '/my-results');
      expect(find.textContaining('not currently enrolled'), findsOneWidget);
    });
  });

  group('performance', () {
    testWidgets('shows pass rate, average, grades and who needs support', (
      tester,
    ) async {
      final r = _ready();
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        exams: r.exams,
        seedMarks: (m) => _seedReady(m, r.exam),
      );
      final scheme = _scheme();
      final subjects = r.exams.subjects[r.exam.examId]!.values.toList();
      final results = [
        for (final s in ['s1', 's2'])
          ResultCalculator.calculate(
            scheme: scheme,
            subjects: subjects,
            entries: {
              for (final sub in subjects)
                sub.subjectId: w
                    .marks
                    .entries['${MarksSheet.idFor(r.exam.examId, sub.subjectId, 'sa')}__$s'],
            },
            studentId: s,
            studentName: s == 's1' ? 'Anil Kumar' : 'Bela Kumar',
            sectionId: 'sa',
          ),
      ];
      await w.results.finalize(
        exam: r.exam,
        scheme: scheme,
        results: results,
        attendance: const {},
        remarks: const {},
        classLabels: const {},
        actor: const ExamActor(userId: 'a', name: 'A', role: 'SCHOOL_ADMIN'),
      );
      await w.go(tester, '/exams/performance');
      expect(find.text('Pass rate'), findsWidgets);
      expect(find.text('50%'), findsWidgets);
      expect(
        find.text('Students who may need academic support'),
        findsOneWidget,
      );
      expect(find.text('Bela Kumar'), findsOneWidget);
    });

    testWidgets('empty state before any result exists', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/exams/performance');
      expect(find.textContaining('Performance appears here'), findsOneWidget);
    });
  });

  group('responsive', () {
    for (final size in const [
      Size(390, 800),
      Size(820, 1100),
      Size(1400, 900),
    ]) {
      testWidgets('screens lay out at ${size.width.toInt()}px', (tester) async {
        final r = _ready();
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          exams: r.exams,
          size: size,
          seedMarks: (m) => _seedReady(m, r.exam),
        );
        for (final p in [
          '/exams',
          '/exams/new',
          '/exams/schemes',
          '/exams/detail/${r.exam.examId}',
          '/exams/review/${r.exam.examId}',
          '/exams/results/${r.exam.examId}',
          '/exams/results/${r.exam.examId}/s1',
          '/exams/marks/${r.exam.examId}/math/sa',
          '/exams/history/${r.exam.examId}',
          '/exams/performance',
        ]) {
          await w.go(tester, p);
          expect(tester.takeException(), isNull, reason: p);
        }
      });
    }
  });
}

/// A fixed actor for repository calls made directly from a test.
class ExamActorForTest {
  const ExamActorForTest();
  ExamActor get actor =>
      const ExamActor(userId: 'a', name: 'Admin', role: 'SCHOOL_ADMIN');
}
