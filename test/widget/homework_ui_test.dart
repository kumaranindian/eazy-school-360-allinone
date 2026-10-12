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
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
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
import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/homework/domain/homework.dart';
import 'package:eazy_school_360/features/homework/domain/homework_enums.dart';
import 'package:eazy_school_360/features/homework/domain/homework_repositories.dart';
import 'package:eazy_school_360/features/homework/domain/homework_submission.dart';
import 'package:eazy_school_360/features/homework/presentation/providers/homework_providers.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/leave_fakes.dart';
import '../support/staff_fakes.dart';
import '../support/homework_fakes.dart';
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

class _World {
  final ProviderContainer container;
  final FakeHomeworkRepository homework;
  final FakeSubmissionRepository submissions;
  final FakeAnnouncementRepository announcements;
  final FakeHomeworkFileStore files;

  _World(
    this.container,
    this.homework,
    this.submissions,
    this.announcements,
    this.files,
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

Student _child({
  String id = 'stu-1',
  String first = 'Anil',
  String? section = 'sa',
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
  currentAcademicYearId: section == null ? null : 'y1',
  currentClassId: section == null ? null : 'c5',
  currentSectionId: section,
);

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  FakeHomeworkRepository? homework,
  FakeSubmissionRepository? submissions,
  FakeAnnouncementRepository? announcements,
  List<TeacherAssignment>? assignments,
  List<Student> children = const [],
  List<Student> roster = const [],
  String? linkedParentId,
  String? ownStaffId,
  Size size = const Size(1400, 1000),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final hw = homework ?? FakeHomeworkRepository();
  final subs = submissions ?? FakeSubmissionRepository();
  final anns = announcements ?? FakeAnnouncementRepository();
  final store = FakeHomeworkFileStore();
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
      studentRepositoryProvider.overrideWithValue(
        FakeStudentRepository(roster),
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
              userId: ownStaffId == 't2' ? _uid : 'u-t2',
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
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
      leaveNotificationRepositoryProvider.overrideWithValue(
        FakeLeaveNotificationRepository(),
      ),
      homeworkRepositoryProvider.overrideWithValue(hw),
      submissionRepositoryProvider.overrideWithValue(subs),
      announcementRepositoryProvider.overrideWithValue(anns),
      homeworkFileStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, hw, subs, anns, store);
}

String _key(int addDays) =>
    AttendanceDate.key(DateTime.now().add(Duration(days: addDays)));

Homework _h(
  String batch, {
  String section = 'sa',
  String subject = 'math',
  String subjectName = 'Maths',
  String teacher = 't1',
  HomeworkStatus status = HomeworkStatus.published,
  int dueInDays = 3,
  String title = 'Chapter 4 exercises',
  int? maxMarks = 10,
  bool allowLate = false,
  bool allowResubmission = true,
  bool requiresSubmission = true,
}) => Homework(
  homeworkId: Homework.idFor(batch, section),
  batchId: batch,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: section,
  classLabel: 'Class 5 – ${section.toUpperCase()}',
  subjectId: subject,
  subjectName: subjectName,
  teacherStaffId: teacher,
  teacherName: 'Meera Iyer',
  title: title,
  description: 'Do all the questions.',
  assignedDateKey: _key(-5),
  dueDateKey: _key(dueInDays),
  dueAt: Homework.dueInstant(_key(dueInDays), null),
  status: status,
  maxMarks: maxMarks,
  allowLate: allowLate,
  allowResubmission: allowResubmission,
  requiresSubmission: requiresSubmission,
);

HomeworkSubmission _s(
  Homework h,
  SubmissionStatus status, {
  String student = 'stu-1',
  String name = 'Anil Kumar',
  String text = 'My answer',
  int? marks,
  String? feedback,
}) => HomeworkSubmission(
  submissionId: HomeworkSubmission.idFor(h.homeworkId, student),
  homeworkId: h.homeworkId,
  studentId: student,
  studentName: name,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: h.sectionId,
  status: status,
  textAnswer: text,
  late: status == SubmissionStatus.lateSubmitted,
  submittedBy: _uid,
  submittedAt: DateTime.now().subtract(const Duration(hours: 2)),
  marks: marks,
  feedback: feedback,
  gradedByName: marks == null ? null : 'Meera Iyer',
);

Announcement _a(
  String id,
  AnnouncementAudience audience, {
  String title = 'Sports day',
  AnnouncementStatus status = AnnouncementStatus.published,
  String? classId,
  String? sectionId,
  DateTime? publishAt,
  DateTime? expiresAt,
  String author = 'someone',
}) => Announcement(
  announcementId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: classId == null ? null : 'y1',
  audience: audience,
  classId: classId,
  sectionId: sectionId,
  title: title,
  body: 'Body of $title',
  status: status,
  publishAt: publishAt ?? DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: expiresAt,
  authorId: author,
  authorName: 'Office',
  authorRole: 'SCHOOL_ADMIN',
);

/// Taps a control, scrolling the page to it first (long forms build their
/// children lazily).
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

/// The form's "Hand in" button (a `FilledButton.icon`, which `byType` does
/// not match).
final _handInButton = find
    .ancestor(
      of: find.text('Hand in'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  group('route and navigation permissions', () {
    testWidgets('a parent reaches homework and announcements, nothing else', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
      );
      for (final p in ['/my-homework', '/announcements']) {
        await w.go(tester, p);
        expect(w.location, p);
      }
      for (final p in [
        '/homework',
        '/homework/new',
        '/homework/edit/x',
        '/homework/detail/x',
        '/homework/review/x',
        '/homework/review/x/stu-1',
        '/announcements/new',
        '/announcements/edit/x',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets('a teacher authors and reviews, but has no family view', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      for (final p in ['/homework', '/homework/new', '/announcements']) {
        await w.go(tester, p);
        expect(w.location, p);
      }
      await w.go(tester, '/my-homework');
      expect(w.location, '/dashboard');
    });

    testWidgets('finance reads announcements only', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      await w.go(tester, '/announcements');
      expect(w.location, '/announcements');
      for (final p in ['/homework', '/my-homework', '/announcements/new']) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });
  });

  group('teacher homework list', () {
    testWidgets('lists the teacher\'s own homework with status and counts', (
      tester,
    ) async {
      final repo = FakeHomeworkRepository(
        homework: [
          _h('b1'),
          _h('b2', status: HomeworkStatus.draft, title: 'Draft worksheet'),
          _h(
            'b3',
            teacher: 't2',
            subject: 'eng',
            title: 'Essay (other teacher)',
          ),
        ],
      );
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        homework: repo,
      );
      await w.go(tester, '/homework');
      expect(find.text('Chapter 4 exercises'), findsWidgets);
      expect(find.text('Draft worksheet'), findsOneWidget);
      expect(find.text('Essay (other teacher)'), findsNothing);
      expect(find.text('Published'), findsWidgets);
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('New homework'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework');
      expect(find.textContaining('No homework matches'), findsOneWidget);
    });

    testWidgets('a teacher without a staff record is told why', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher);
      await w.go(tester, '/homework');
      expect(
        find.textContaining("isn't linked to a staff record"),
        findsOneWidget,
      );
    });

    testWidgets('an admin sees every teacher\'s homework', (tester) async {
      final repo = FakeHomeworkRepository(
        homework: [
          _h('b1'),
          _h(
            'b3',
            teacher: 't2',
            subject: 'eng',
            title: 'Essay (other teacher)',
          ),
        ],
      );
      final w = await _pump(tester, role: UserRole.branchAdmin, homework: repo);
      await w.go(tester, '/homework');
      expect(find.text('Chapter 4 exercises'), findsWidgets);
      expect(find.text('Essay (other teacher)'), findsWidgets);
    });
  });

  group('creating homework', () {
    testWidgets('a teacher is offered only their own sections and subjects', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework/new');
      expect(find.text('Class 5 – SA — Maths'), findsOneWidget);
      expect(find.textContaining('English'), findsNothing);
      expect(find.textContaining('SB'), findsNothing);
    });

    testWidgets('an admin may set homework for any assigned teacher', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/homework/new');
      expect(find.text('Class 5 – SA — Maths'), findsOneWidget);
      expect(find.text('Class 5 – SA — English'), findsOneWidget);
      expect(find.text('Class 5 – SB — Maths'), findsOneWidget);
    });

    testWidgets('validation blocks an empty form and writes nothing', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework/new');
      await _tap(tester, find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter at least 3 characters'),
        findsOneWidget,
      );
      expect(w.homework.createdBatches, isEmpty);
    });

    testWidgets('needs a section and a due date', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework/new');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Fractions',
      );
      await _tap(tester, find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a due date.'), findsOneWidget);
      expect(w.homework.createdBatches, isEmpty);

      await _tap(tester, find.text('Choose due date'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('OK'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose at least one section and subject.'),
        findsOneWidget,
      );
      expect(w.homework.createdBatches, isEmpty);
    });

    testWidgets('saves a draft for the chosen section', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework/new');
      await _tap(tester, find.text('Class 5 – SA — Maths'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Fractions',
      );
      await _tap(tester, find.text('Choose due date'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('OK'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(w.homework.createdBatches.length, 1);
      final created = w.homework.createdBatches.single.single;
      expect(created.title, 'Fractions');
      expect(created.sectionId, 'sa');
      expect(created.subjectId, 'math');
      expect(created.teacherStaffId, 't1');
      expect(created.status, HomeworkStatus.draft);
      expect(w.homework.published, isEmpty);
      expect(w.location, '/homework');
    });

    testWidgets('preview comes before publishing; cancelling writes nothing', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/homework/new');
      await _tap(tester, find.text('Class 5 – SA — Maths'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Fractions',
      );
      await _tap(tester, find.text('Choose due date'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('OK'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Preview & publish'));
      await tester.pumpAndSettle();
      expect(find.text('Review before publishing'), findsOneWidget);
      expect(find.text('Who will see it'), findsOneWidget);
      expect(find.text('Fractions'), findsOneWidget);
      await _tap(tester, find.text('Back to edit'));
      await tester.pumpAndSettle();
      expect(w.homework.createdBatches, isEmpty);

      await _tap(tester, find.text('Preview & publish'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Publish to 1 section(s)'));
      await tester.pumpAndSettle();
      expect(w.homework.createdBatches.length, 1);
      expect(w.homework.published, [
        w.homework.createdBatches.single.single.homeworkId,
      ]);
    });
  });

  group('homework detail and lifecycle', () {
    testWidgets(
      'a draft can be previewed and published; a retry does not republish',
      (tester) async {
        final draft = _h('b1', status: HomeworkStatus.draft);
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          ownStaffId: 't1',
          homework: FakeHomeworkRepository(homework: [draft]),
        );
        await w.go(tester, '/homework/detail/${draft.homeworkId}');
        expect(find.text('Families cannot see this yet.'), findsOneWidget);
        await _tap(tester, find.text('Preview & publish'));
        await tester.pumpAndSettle();
        await _tap(tester, find.textContaining('Publish to 1 section'));
        await tester.pumpAndSettle();
        expect(w.homework.published, [draft.homeworkId]);
        // publishing again is a no-op in the repository
        await w.homework.publish(
          homework: draft,
          actor: const HomeworkActor(userId: _uid, name: 'T', role: 'TEACHER'),
        );
        expect(w.homework.published.length, 1);
      },
    );

    testWidgets('close asks for confirmation', (tester) async {
      final h = _h('b1');
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        homework: FakeHomeworkRepository(homework: [h]),
      );
      await w.go(tester, '/homework/detail/${h.homeworkId}');
      await _tap(tester, find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Close this homework?'), findsOneWidget);
      await _tap(tester, _inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(w.homework.closed, isEmpty);
      await _tap(tester, find.text('Close'));
      await tester.pumpAndSettle();
      await _tap(tester, _inDialog('Close'));
      await tester.pumpAndSettle();
      expect(w.homework.closed, [h.homeworkId]);
    });

    testWidgets('a published homework offers extension, not shortening', (
      tester,
    ) async {
      final h = _h('b1');
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        homework: FakeHomeworkRepository(homework: [h]),
      );
      await w.go(tester, '/homework/edit/${h.homeworkId}');
      expect(find.text('This homework is published'), findsOneWidget);
      // title and marks are fixed
      final title = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Title'),
      );
      expect(title.enabled, isFalse);
    });
  });

  group('review', () {
    Future<_World> reviewWorld(
      WidgetTester tester, {
      List<Student> roster = const [],
    }) {
      final h = _h('b1');
      return _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        homework: FakeHomeworkRepository(homework: [h]),
        submissions: FakeSubmissionRepository(
          submissions: [_s(h, SubmissionStatus.submitted)],
        ),
        roster: roster,
      );
    }

    testWidgets(
      'lists submissions with status; not-submitted derives from the roster',
      (tester) async {
        final w = await reviewWorld(
          tester,
          roster: [
            _child(),
            _child(id: 'stu-2', first: 'Bela'),
            _child(id: 'stu-3', first: 'Chitra', status: StudentStatus.left),
          ],
        );
        await w.go(tester, '/homework/review/b1__sa');
        expect(find.text('Anil Kumar'), findsOneWidget);
        expect(find.text('Submitted'), findsWidgets);
        await _tap(tester, find.text('Not submitted'));
        await tester.pumpAndSettle();
        expect(find.text('Bela Kumar'), findsOneWidget);
        // handed in, and withdrawn students, are not listed as missing
        expect(find.text('Anil Kumar'), findsNothing);
        expect(find.text('Chitra Kumar'), findsNothing);
      },
    );

    testWidgets('marks outside 0..max are refused and nothing is written', (
      tester,
    ) async {
      final w = await reviewWorld(tester);
      await w.go(tester, '/homework/review/b1__sa/stu-1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Marks (0 – 10)'),
        '11',
      );
      await _tap(tester, find.text('Grade'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between 0 and 10'), findsOneWidget);
      expect(w.submissions.graded, isEmpty);
    });

    testWidgets('grading records the grade and keeps the history', (
      tester,
    ) async {
      final w = await reviewWorld(tester);
      await w.go(tester, '/homework/review/b1__sa/stu-1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Marks (0 – 10)'),
        '8',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Feedback'),
        'Well done',
      );
      await _tap(tester, find.text('Grade'));
      await tester.pumpAndSettle();
      expect(w.submissions.graded.length, 1);
      final s = w.submissions.docs['b1__sa__stu-1']!;
      expect(s.status, SubmissionStatus.graded);
      expect(s.marks, 8);
      expect(s.feedback, 'Well done');
      expect(s.revision, 2);
      expect(w.submissions.revisions['b1__sa__stu-1']!.length, 1);
    });

    testWidgets(
      'returning for revision needs a reason, then waits for the student',
      (tester) async {
        final w = await reviewWorld(tester);
        await w.go(tester, '/homework/review/b1__sa/stu-1');
        await _tap(tester, find.text('Return for revision'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Tell the student what to revise'),
          findsOneWidget,
        );
        expect(w.submissions.returned, isEmpty);
        await tester.enterText(
          find.widgetWithText(TextField, 'Feedback'),
          'Show your working',
        );
        await _tap(tester, find.text('Return for revision'));
        await tester.pumpAndSettle();
        expect(w.submissions.returned.length, 1);
        expect(find.text('Waiting for the student'), findsOneWidget);
      },
    );
  });

  group('family view', () {
    testWidgets('states: to do, overdue, submitted, needs revision, graded', (
      tester,
    ) async {
      final todo = _h('b1', title: 'Todo work');
      final overdue = _h('b2', title: 'Overdue work', dueInDays: -2);
      final done = _h('b3', title: 'Done work');
      final back = _h('b4', title: 'Revise work');
      final graded = _h('b5', title: 'Graded work');
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        homework: FakeHomeworkRepository(
          homework: [
            todo,
            overdue,
            done,
            back,
            graded,
            // not this child's section, and a draft: never listed
            _h('b6', section: 'sb', title: 'Other section work'),
            _h('b7', status: HomeworkStatus.draft, title: 'Draft work'),
          ],
        ),
        submissions: FakeSubmissionRepository(
          submissions: [
            _s(done, SubmissionStatus.submitted),
            _s(back, SubmissionStatus.returnedForRevision, feedback: 'Redo'),
            _s(graded, SubmissionStatus.graded, marks: 9, feedback: 'Great'),
          ],
        ),
      );
      await w.go(tester, '/my-homework');
      for (final t in [
        'Todo work',
        'Overdue work',
        'Done work',
        'Revise work',
        'Graded work',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Other section work'), findsNothing);
      expect(find.text('Draft work'), findsNothing);
      expect(find.text('To do'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Needs revision'), findsWidgets);
      expect(find.text('9/10'), findsOneWidget);
    });

    testWidgets(
      'opening a homework does not submit it; submitting needs confirmation and happens once',
      (tester) async {
        final h = _h('b1');
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'p1',
          children: [_child()],
          homework: FakeHomeworkRepository(homework: [h]),
        );
        await w.go(tester, '/my-homework/${h.homeworkId}/stu-1');
        expect(w.submissions.submitted, isEmpty);
        expect(find.text('Do all the questions.'), findsOneWidget);

        // an empty answer is refused
        await _tap(tester, _handInButton);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Write an answer or attach a file'),
          findsOneWidget,
        );
        expect(w.submissions.submitted, isEmpty);

        await tester.enterText(
          find.widgetWithText(TextField, 'Your answer'),
          '3/4 + 1/4 = 1',
        );
        await _tap(tester, _handInButton);
        await tester.pumpAndSettle();
        expect(find.text('Hand in this homework?'), findsOneWidget);
        await _tap(tester, _inDialog('Cancel'));
        await tester.pumpAndSettle();
        expect(w.submissions.submitted, isEmpty);

        await _tap(tester, _handInButton);
        await tester.pumpAndSettle();
        await _tap(tester, _inDialog('Hand in'));
        await tester.pumpAndSettle();
        expect(w.submissions.submitted.length, 1);
        final s = w.submissions.docs['${h.homeworkId}__stu-1']!;
        expect(s.textAnswer, '3/4 + 1/4 = 1');
        expect(s.status, SubmissionStatus.submitted);
        expect(s.submittedBy, _uid);
      },
    );

    testWidgets('after the deadline, no late work means no form', (
      tester,
    ) async {
      final h = _h('b1', dueInDays: -1);
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        homework: FakeHomeworkRepository(homework: [h]),
      );
      await w.go(tester, '/my-homework/${h.homeworkId}/stu-1');
      expect(find.textContaining('deadline has passed'), findsOneWidget);
      expect(find.text('Hand in'), findsNothing);
    });

    testWidgets('late work is accepted when the homework allows it', (
      tester,
    ) async {
      final h = _h('b1', dueInDays: -1, allowLate: true);
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        homework: FakeHomeworkRepository(homework: [h]),
      );
      await w.go(tester, '/my-homework/${h.homeworkId}/stu-1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Your answer'),
        'Late answer',
      );
      await _tap(tester, _handInButton);
      await tester.pumpAndSettle();
      await _tap(tester, _inDialog('Hand in'));
      await tester.pumpAndSettle();
      expect(
        w.submissions.docs['${h.homeworkId}__stu-1']!.status,
        SubmissionStatus.lateSubmitted,
      );
    });

    testWidgets(
      'returned work shows feedback and can be revised; graded work is locked',
      (tester) async {
        final back = _h('b1');
        final graded = _h('b2', title: 'Graded one');
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'p1',
          children: [_child()],
          homework: FakeHomeworkRepository(homework: [back, graded]),
          submissions: FakeSubmissionRepository(
            submissions: [
              _s(
                back,
                SubmissionStatus.returnedForRevision,
                feedback: 'Show your working',
              ),
              _s(graded, SubmissionStatus.graded, marks: 9, feedback: 'Great'),
            ],
          ),
        );
        await w.go(tester, '/my-homework/${back.homeworkId}/stu-1');
        expect(find.text('Show your working'), findsOneWidget);
        expect(find.text('Revise and resubmit'), findsOneWidget);

        await w.go(tester, '/my-homework/${graded.homeworkId}/stu-1');
        expect(find.text('Marks: 9 / 10'), findsOneWidget);
        expect(find.text('Great'), findsOneWidget);
        expect(find.textContaining('Change and resubmit'), findsNothing);
        expect(
          find.textContaining('Graded work cannot be changed'),
          findsOneWidget,
        );
      },
    );

    testWidgets('another section\'s homework is not available by link', (
      tester,
    ) async {
      final other = _h('b9', section: 'sb');
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        homework: FakeHomeworkRepository(homework: [other]),
      );
      await w.go(tester, '/my-homework/${other.homeworkId}/stu-1');
      expect(find.text('This homework is not available.'), findsOneWidget);
    });

    testWidgets('a child that is not linked cannot be opened', (tester) async {
      final h = _h('b1');
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        homework: FakeHomeworkRepository(homework: [h]),
      );
      await w.go(tester, '/my-homework/${h.homeworkId}/stu-99');
      expect(
        find.text('This child is not linked to your account.'),
        findsOneWidget,
      );
    });

    testWidgets('an unplaced child has no homework yet', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child(section: null)],
      );
      await w.go(tester, '/my-homework');
      expect(find.textContaining('not been placed in a class'), findsOneWidget);
    });

    testWidgets('no homework yet is an empty state, not an error', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
      );
      await w.go(tester, '/my-homework');
      expect(find.text('No homework to show.'), findsOneWidget);
    });

    testWidgets('a withdrawn child has no active homework', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child(status: StudentStatus.left)],
        homework: FakeHomeworkRepository(homework: [_h('b1')]),
      );
      await w.go(tester, '/my-homework');
      expect(find.textContaining('not currently enrolled'), findsOneWidget);
      expect(find.text('Chapter 4 exercises'), findsNothing);
    });
  });

  group('announcements', () {
    testWidgets(
      'a parent sees only current announcements addressed to their child',
      (tester) async {
        final anns = FakeAnnouncementRepository(
          announcements: [
            _a('a1', AnnouncementAudience.all, title: 'School closed Friday'),
            _a('a2', AnnouncementAudience.parents, title: 'Parent meeting'),
            _a(
              'a3',
              AnnouncementAudience.section,
              title: 'Class 5 A trip',
              classId: 'c5',
              sectionId: 'sa',
            ),
            _a(
              'a4',
              AnnouncementAudience.section,
              title: 'Class 5 B trip',
              classId: 'c5',
              sectionId: 'sb',
            ),
            _a('a5', AnnouncementAudience.staff, title: 'Staff meeting'),
            _a(
              'a6',
              AnnouncementAudience.all,
              title: 'Old notice',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
            _a(
              'a7',
              AnnouncementAudience.all,
              title: 'Future notice',
              publishAt: DateTime.now().add(const Duration(days: 2)),
            ),
            _a(
              'a8',
              AnnouncementAudience.all,
              title: 'Draft notice',
              status: AnnouncementStatus.draft,
            ),
          ],
        );
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'p1',
          children: [_child()],
          announcements: anns,
        );
        await w.go(tester, '/announcements');
        for (final t in [
          'School closed Friday',
          'Parent meeting',
          'Class 5 A trip',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        for (final t in [
          'Class 5 B trip',
          'Staff meeting',
          'Old notice',
          'Future notice',
          'Draft notice',
        ]) {
          expect(find.text(t), findsNothing, reason: t);
        }
        expect(find.text('New announcement'), findsNothing);
      },
    );

    testWidgets('managers can review drafts, scheduled, expired and archived', (
      tester,
    ) async {
      final anns = FakeAnnouncementRepository(
        announcements: [
          _a('a1', AnnouncementAudience.all, title: 'Live notice'),
          _a(
            'a2',
            AnnouncementAudience.all,
            title: 'Draft notice',
            status: AnnouncementStatus.draft,
          ),
          _a(
            'a3',
            AnnouncementAudience.all,
            title: 'Old notice',
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        announcements: anns,
      );
      await w.go(tester, '/announcements');
      expect(find.text('Live notice'), findsOneWidget);
      expect(find.text('Draft notice'), findsNothing);
      await _tap(tester, find.text('Drafts'));
      await tester.pumpAndSettle();
      expect(find.text('Draft notice'), findsOneWidget);
      await _tap(tester, find.text('Expired'));
      await tester.pumpAndSettle();
      expect(find.text('Old notice'), findsOneWidget);
      expect(find.text('New announcement'), findsOneWidget);
    });

    testWidgets('a teacher who is not a class teacher cannot post', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await w.go(tester, '/announcements/new');
      expect(find.textContaining('class teacher'), findsOneWidget);
    });

    testWidgets('a class teacher is limited to their own section', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        assignments: [_assign('t1', 'sa', 'math', classTeacher: true)],
      );
      await w.go(tester, '/announcements/new');
      expect(find.text('A section (parents and its teachers)'), findsWidgets);
      expect(find.text('Everyone in the school'), findsNothing);
    });

    testWidgets(
      'create → preview → publish; nothing is published before confirmation',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/announcements/new');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'Fee reminder',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Message'),
          'Fees are due on the 5th.',
        );
        await _tap(tester, find.text('Preview & publish'));
        await tester.pumpAndSettle();
        expect(find.text('Review before publishing'), findsOneWidget);
        await _tap(tester, find.text('Back to edit'));
        await tester.pumpAndSettle();
        expect(w.announcements.published, isEmpty);
        await _tap(tester, find.text('Preview & publish'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Publish now'));
        await tester.pumpAndSettle();
        expect(w.announcements.published.length, 1);
      },
    );

    testWidgets('a branch admin cannot address the whole school', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/announcements/new');
      await _tap(
        tester,
        find.byType(DropdownButtonFormField<AnnouncementAudience>),
      );
      await tester.pumpAndSettle();
      expect(find.text('Everyone in the school'), findsNothing);
      expect(find.text('This branch (staff and parents)'), findsWidgets);
    });
  });

  group('responsive', () {
    for (final size in const [
      Size(390, 800),
      Size(820, 1100),
      Size(1400, 900),
    ]) {
      testWidgets('lists and forms lay out at ${size.width.toInt()}px', (
        tester,
      ) async {
        final h = _h('b1');
        final w = await _pump(
          tester,
          role: UserRole.teacher,
          ownStaffId: 't1',
          size: size,
          homework: FakeHomeworkRepository(homework: [h]),
          submissions: FakeSubmissionRepository(
            submissions: [_s(h, SubmissionStatus.submitted)],
          ),
        );
        for (final p in [
          '/homework',
          '/homework/new',
          '/homework/detail/${h.homeworkId}',
          '/homework/review/${h.homeworkId}',
          '/homework/review/${h.homeworkId}/stu-1',
          '/announcements',
          '/announcements/new',
        ]) {
          await w.go(tester, p);
          expect(tester.takeException(), isNull, reason: p);
        }
      });
    }

    testWidgets('the family screens lay out on a phone', (tester) async {
      final h = _h('b1');
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'p1',
        children: [_child()],
        size: const Size(390, 800),
        homework: FakeHomeworkRepository(homework: [h]),
      );
      for (final p in [
        '/my-homework',
        '/my-homework/${h.homeworkId}/stu-1',
        '/announcements',
      ]) {
        await w.go(tester, p);
        expect(tester.takeException(), isNull, reason: p);
      }
    });
  });
}
