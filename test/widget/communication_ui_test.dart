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
import 'package:eazy_school_360/features/communication/domain/conversation.dart';
import 'package:eazy_school_360/features/communication/presentation/providers/communication_providers.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_category.dart';
import 'package:eazy_school_360/features/notifications/presentation/providers/notification_providers.dart';
import '../support/communication_fakes.dart';
import '../support/homework_fakes.dart' show FakeAnnouncementRepository;
import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/homework/presentation/providers/homework_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
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

class _World {
  final ProviderContainer container;
  final FakeNotificationRepository notifications;
  final FakeCommunicationRepository comms;

  _World(this.container, this.notifications, this.comms);

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

FeedItem _note(
  String id,
  String type,
  String title, {
  bool read = false,
  int minutesAgo = 1,
  String? conversationId,
  String? refId,
}) => FeedItem(
  id: id,
  source: FeedSource.targeted,
  branchId: 'main',
  type: type,
  title: title,
  body: 'Short line',
  createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  read: read,
  conversationId: conversationId,
  refId: refId,
);

Conversation _conversation({
  String id = 'cv_1',
  ConversationStatus status = ConversationStatus.open,
  int unreadForParent = 0,
  int unreadForTeacher = 0,
  bool flagged = false,
  String parent = _uid,
  String teacher = 'u-t1',
}) => Conversation(
  conversationId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: 'sa',
  studentId: 's1',
  studentName: 'Anil Kumar',
  parentUserId: parent,
  parentName: 'Test User',
  teacherUserId: teacher,
  teacherStaffId: 't1',
  teacherName: 'Meera Iyer',
  subjectId: 'math',
  subjectName: 'Maths',
  title: 'Homework help',
  status: status,
  messageCount: 1,
  lastMessageId: 'm_0',
  lastMessageAt: DateTime.now(),
  unreadForParent: unreadForParent,
  unreadForTeacher: unreadForTeacher,
  flagged: flagged,
);

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  FakeNotificationRepository? notifications,
  FakeCommunicationRepository? comms,
  List<BroadcastNotice> notices = const [],
  List<Student> children = const [],
  String? linkedParentId,
  String? ownStaffId,
  Size size = const Size(1400, 1000),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final n = notifications ?? FakeNotificationRepository();
  final c = comms ?? FakeCommunicationRepository();
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
            Section(
              sectionId: 'sa',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              classId: 'c5',
              name: 'A',
              status: ActivationStatus.active,
            ),
          ],
          subjects: [
            Subject(
              subjectId: 'math',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              name: 'Maths',
              type: SubjectType.core,
              displayOrder: 1,
              status: ActivationStatus.active,
            ),
          ],
          classSubjectIds: const {
            'c5': ['math'],
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
      studentRepositoryProvider.overrideWithValue(FakeStudentRepository([])),
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
          ],
        ),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(
        FakeTeacherAssignmentRepository()
          ..existing = [_assign('t1', 'sa', 'math')],
      ),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
      leaveNotificationRepositoryProvider.overrideWithValue(
        FakeLeaveNotificationRepository(),
      ),
      announcementRepositoryProvider.overrideWithValue(
        FakeAnnouncementRepository(notices: notices),
      ),
      notificationRepositoryProvider.overrideWithValue(n),
      communicationRepositoryProvider.overrideWithValue(c),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, n, c);
}

final _kid = _student('s1', 'Anil');

void main() {
  group('route and navigation permissions', () {
    for (final role in [UserRole.teacher, UserRole.finance, UserRole.parent]) {
      testWidgets('a $role has a notification centre', (tester) async {
        final w = await _pump(
          tester,
          role: role,
          linkedParentId: role == UserRole.parent ? 'par1' : null,
          children: role == UserRole.parent ? [_kid] : const [],
        );
        await w.go(tester, '/notifications');
        expect(w.location, '/notifications');
        expect(
          find.text("You're all caught up. Nothing to show here."),
          findsOneWidget,
        );
      });
    }

    testWidgets('finance staff cannot open messages', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      await w.go(tester, '/messages');
      expect(w.location, isNot('/messages'));
    });

    testWidgets('a parent can open messages', (tester) async {
      final p = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
      );
      await p.go(tester, '/messages');
      expect(p.location, '/messages');
    });

    testWidgets('a teacher can open messages', (tester) async {
      final t = await _pump(tester, role: UserRole.teacher, ownStaffId: 't1');
      await t.go(tester, '/messages');
      expect(t.location, '/messages');
    });
  });

  group('notification centre', () {
    FakeNotificationRepository seeded() => FakeNotificationRepository({
      _uid: [
        _note(
          'n1',
          'HOMEWORK_PUBLISHED',
          'New homework in Maths',
          minutesAgo: 5,
        ),
        _note('n2', 'RESULT_PUBLISHED', 'Results published', minutesAgo: 3),
        _note(
          'n3',
          'MESSAGE_RECEIVED',
          'New message from Meera Iyer',
          minutesAgo: 1,
          conversationId: 'cv_1',
        ),
        _note(
          'n4',
          'LEAVE_APPROVED',
          'Leave approved',
          read: true,
          minutesAgo: 9,
        ),
      ],
      'someone-else': [
        _note('x1', 'HOMEWORK_PUBLISHED', "Someone else's notice"),
      ],
    });

    testWidgets(
      'lists only my notifications, newest first, with unread count',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'par1',
          children: [_kid],
          notifications: seeded(),
        );
        await w.go(tester, '/notifications');
        expect(find.text("Someone else's notice"), findsNothing);
        expect(find.text('Unread (3)'), findsOneWidget);
        final newest = tester
            .getTopLeft(find.text('New message from Meera Iyer'))
            .dy;
        final oldest = tester.getTopLeft(find.text('New homework in Maths')).dy;
        expect(newest, lessThan(oldest));
      },
    );

    testWidgets('opening a notification marks it read and goes to its screen', (
      tester,
    ) async {
      final repo = seeded();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: repo,
        comms: FakeCommunicationRepository()
          ..conversations['cv_1'] = _conversation(),
      );
      await w.go(tester, '/notifications');
      await tester.tap(find.text('New message from Meera Iyer'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('markRead:n3'));
      expect(w.location, startsWith('/messages/cv_1'));
    });

    testWidgets('a notification whose record is gone opens a safe screen', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: seeded(),
      );
      await w.go(tester, '/notifications');
      await tester.tap(find.text('New message from Meera Iyer'));
      await tester.pumpAndSettle();
      expect(find.text('This conversation is not available.'), findsOneWidget);
    });

    testWidgets('mark all read asks first, and changes only my notifications', (
      tester,
    ) async {
      final repo = seeded();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: repo,
      );
      await w.go(tester, '/notifications');
      await tester.tap(find.byTooltip('Mark all as read'));
      await tester.pumpAndSettle();
      expect(find.text('Mark all as read?'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('markAll')), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark all as read'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('markAll:$_uid'));
      expect(repo.byUser['someone-else']!.single.read, isFalse);
      expect(find.text('Unread (0)'), findsOneWidget);
    });

    testWidgets('a muted category disappears from the list and the count', (
      tester,
    ) async {
      final repo = seeded();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: repo,
      );
      await w.go(tester, '/notifications/preferences');
      expect(find.text('Not available'), findsWidgets);
      final tile = find.widgetWithText(SwitchListTile, 'Homework');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(repo.prefs[_uid]!.muted, contains(NotificationCategory.homework));
      await w.go(tester, '/notifications');
      expect(find.text('New homework in Maths'), findsNothing);
      expect(find.text('Unread (2)'), findsOneWidget);
    });

    testWidgets('administrative notices cannot be switched off', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.teacher);
      await w.go(tester, '/notifications/preferences');
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Administrative notices'),
      );
      expect(tile.onChanged, isNull);
    });

    testWidgets('a failed mark-read still opens the item', (tester) async {
      final repo = seeded()..failMarkRead = StateError('offline');
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: repo,
      );
      await w.go(tester, '/notifications');
      await tester.tap(find.text('New message from Meera Iyer'));
      await tester.pumpAndSettle();
      expect(w.location, startsWith('/messages/cv_1'));
    });

    testWidgets('the bell shows my unread count and no overflow at 390px', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        notifications: seeded(),
        size: const Size(390, 800),
      );
      await w.go(tester, '/notifications');
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Notifications, 3 unread'), findsWidgets);
    });

    testWidgets(
      'the bell and the centre share one bounded listener per branch',
      (tester) async {
        final repo = seeded();
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'par1',
          children: [_kid],
          notifications: repo,
        );
        await w.go(tester, '/notifications');
        expect(repo.watchers, 1);
        w.container.dispose();
        await tester.pump();
        expect(repo.cancelled, repo.watchers);
      },
    );
  });

  group('parent–teacher conversations', () {
    MessageContact contact({bool enabled = true}) => MessageContact(
      staffId: 't1',
      userId: 'u-t1',
      name: 'Meera Iyer',
      enabled: enabled,
      sectionKeys: const ['y1__c5__sa'],
      scopes: const ['y1__c5__sa__math'],
      subjectNames: const {'y1__c5__sa__math': 'Maths'},
    );

    testWidgets(
      'a parent starts a conversation with a teacher of their child',
      (tester) async {
        final comms = FakeCommunicationRepository()..contacts['t1'] = contact();
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'par1',
          children: [_kid],
          comms: comms,
        );
        await w.go(tester, '/messages/new');
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maths — Meera Iyer').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Subject'),
          'Homework help',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Message'),
          'Could you explain Q4?',
        );
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
        expect(comms.conversations, hasLength(1));
        final c = comms.conversations.values.single;
        expect(c.parentUserId, _uid);
        expect(c.studentId, 's1');
        expect(comms.messages[c.conversationId], hasLength(1));
        expect(w.location, startsWith('/messages/${c.conversationId}'));
      },
    );

    testWidgets('teachers who have not opted in are not offered', (
      tester,
    ) async {
      final comms = FakeCommunicationRepository()
        ..contacts['t1'] = contact(enabled: false);
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
      );
      await w.go(tester, '/messages/new');
      expect(
        find.textContaining('taking messages from parents'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    });

    testWidgets('an empty or too-short message is refused before sending', (
      tester,
    ) async {
      final comms = FakeCommunicationRepository()..contacts['t1'] = contact();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
      );
      await w.go(tester, '/messages/new');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maths — Meera Iyer').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Subject'), 'Hi');
      await tester.enterText(find.widgetWithText(TextField, 'Message'), '   ');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(comms.conversations, isEmpty);
    });

    testWidgets(
      'a parent sends in a thread; the send failure keeps the text and a retry creates one message',
      (tester) async {
        final comms = FakeCommunicationRepository()
          ..conversations['cv_1'] = _conversation()
          ..messages['cv_1'] = [
            Message(
              messageId: 'm_0',
              conversationId: 'cv_1',
              senderUserId: _uid,
              senderName: 'Test User',
              body: 'First message',
            ),
          ]
          ..failSends = 1;
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'par1',
          children: [_kid],
          comms: comms,
        );
        await w.go(tester, '/messages/cv_1?branchId=main');
        await tester.enterText(
          find.widgetWithText(TextField, 'Message'),
          'Thanks!',
        );
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
        expect(find.textContaining('not sent'), findsOneWidget);
        expect(find.text('Thanks!'), findsOneWidget); // still in the composer
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        final list = comms.messages['cv_1']!;
        expect(list.where((m) => m.body == 'Thanks!'), hasLength(1));
        expect(comms.sendAttempts, 2);
      },
    );

    testWidgets(
      'a closed conversation has no composer and a parent cannot reopen it',
      (tester) async {
        final comms = FakeCommunicationRepository()
          ..conversations['cv_1'] = _conversation(
            status: ConversationStatus.closed,
          );
        final p = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'par1',
          children: [_kid],
          comms: comms,
        );
        await p.go(tester, '/messages/cv_1?branchId=main');
        expect(find.widgetWithText(TextField, 'Message'), findsNothing);
        expect(find.textContaining('closed'), findsWidgets);
        await tester.tap(find.byTooltip('Conversation actions'));
        await tester.pumpAndSettle();
        expect(find.text('Reopen'), findsNothing);
      },
    );

    testWidgets(
      'the teacher can reopen a closed conversation, which is recorded',
      (tester) async {
        final comms = FakeCommunicationRepository()
          ..conversations['cv_1'] = _conversation(
            status: ConversationStatus.closed,
            teacher: _uid,
            parent: 'other-parent',
          );
        final t = await _pump(
          tester,
          role: UserRole.teacher,
          ownStaffId: 't1',
          comms: comms,
        );
        await t.go(tester, '/messages/cv_1?branchId=main');
        await tester.tap(find.byTooltip('Conversation actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reopen'));
        await tester.pumpAndSettle();
        expect(comms.conversations['cv_1']!.status, ConversationStatus.open);
        expect(comms.events['cv_1'], isNotEmpty);
      },
    );

    testWidgets('closing asks for confirmation', (tester) async {
      final comms = FakeCommunicationRepository()
        ..conversations['cv_1'] = _conversation();
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
      );
      await w.go(tester, '/messages/cv_1?branchId=main');
      await tester.tap(find.byTooltip('Conversation actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Close this conversation?'), findsOneWidget);
      expect(comms.conversations['cv_1']!.status, ConversationStatus.open);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(comms.conversations['cv_1']!.status, ConversationStatus.closed);
    });

    testWidgets("someone else's conversation is not available", (tester) async {
      final comms = FakeCommunicationRepository()
        ..conversations['cv_9'] = _conversation(
          id: 'cv_9',
          parent: 'p-x',
          teacher: 't-x',
        );
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
      );
      await w.go(tester, '/messages/cv_9?branchId=main');
      expect(find.widgetWithText(TextField, 'Message'), findsNothing);
      // not a member: no composer, no reply possible, and no actions to take
      expect(comms.messages['cv_9'], isNull);
    });

    testWidgets('reading clears only my unread counter', (tester) async {
      final comms = FakeCommunicationRepository()
        ..conversations['cv_1'] = _conversation(
          unreadForParent: 2,
          unreadForTeacher: 1,
        );
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
      );
      await w.go(tester, '/messages/cv_1?branchId=main');
      await tester.pumpAndSettle();
      final c = comms.conversations['cv_1']!;
      expect(c.unreadForParent, 0);
      expect(c.unreadForTeacher, 1);
    });

    testWidgets('the list shows unread badges and works at phone width', (
      tester,
    ) async {
      final comms = FakeCommunicationRepository()
        ..conversations['cv_1'] = _conversation(unreadForParent: 3);
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'par1',
        children: [_kid],
        comms: comms,
        size: const Size(390, 800),
      );
      await w.go(tester, '/messages');
      expect(find.text('Homework help'), findsOneWidget);
      expect(find.text('Unread (3)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an administrator sees only reported conversations', (
      tester,
    ) async {
      final comms = FakeCommunicationRepository()
        ..conversations['cv_1'] = _conversation()
        ..conversations['cv_2'] = _conversation(id: 'cv_2', flagged: true);
      final w = await _pump(tester, role: UserRole.schoolAdmin, comms: comms);
      await w.go(tester, '/messages');
      expect(find.text('Reported conversations'), findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(1));
    });

    testWidgets('a teacher chooses whether parents may message them', (
      tester,
    ) async {
      final comms = FakeCommunicationRepository();
      final w = await _pump(
        tester,
        role: UserRole.teacher,
        ownStaffId: 't1',
        comms: comms,
      );
      await w.go(tester, '/messages');
      final sw = find.widgetWithText(
        SwitchListTile,
        'Let parents of my sections message me',
      );
      await tester.tap(sw);
      await tester.pumpAndSettle();
      final saved = comms.contacts['t1']!;
      expect(saved.enabled, isTrue);
      expect(saved.userId, _uid);
      expect(saved.scopes, ['y1__c5__sa__math']);
    });
  });
}
