import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/communication/domain/communication_rules.dart';
import 'package:eazy_school_360/features/communication/domain/conversation.dart';
import 'package:eazy_school_360/features/communication/data/communication_writes.dart';
import 'package:eazy_school_360/features/communication/domain/communication_repository.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_category.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conv({
  ConversationStatus status = ConversationStatus.open,
  bool flagged = false,
}) => Conversation(
  conversationId: 'cv_1',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y',
  classId: 'c',
  sectionId: 'sa',
  studentId: 'st',
  studentName: 'Anil',
  parentUserId: 'p1',
  parentName: 'Parent',
  teacherUserId: 't1',
  teacherStaffId: 'tt',
  teacherName: 'Teacher',
  subjectId: 'math',
  subjectName: 'Maths',
  title: 'Hello',
  status: status,
  flagged: flagged,
);

FeedItem _item(String type, {String source = 'targeted', String? ref}) =>
    FeedItem(
      id: 'n1',
      source: source == 'targeted' ? FeedSource.targeted : FeedSource.shared,
      branchId: 'b',
      type: type,
      title: 't',
      refId: ref,
    );

void main() {
  group('message validation', () {
    test('empty, whitespace-only and over-long messages are refused', () {
      expect(CommunicationRules.validateMessage(''), isNotNull);
      expect(CommunicationRules.validateMessage('   \n\t '), isNotNull);
      expect(
        CommunicationRules.validateMessage(
          'a' * (CommunicationRules.maxMessageLength + 1),
        ),
        isNotNull,
      );
      expect(
        CommunicationRules.validateMessage(
          'a' * CommunicationRules.maxMessageLength,
        ),
        isNull,
      );
    });

    test('at most three attachments', () {
      final files = <FileAttachment>[
        for (var i = 0; i < 4; i++)
          FileAttachment(
            name: 'f$i.pdf',
            path: 'p/$i',
            uploadedBy: 'p1',
            contentType: 'application/pdf',
            sizeBytes: 10,
          ),
      ];
      expect(
        CommunicationRules.validateMessage('hi', attachments: files),
        isNotNull,
      );
      expect(
        CommunicationRules.validateMessage(
          'hi',
          attachments: files.take(3).toList(),
        ),
        isNull,
      );
    });

    test('titles are 3..80 characters', () {
      expect(CommunicationRules.validateTitle('ab'), isNotNull);
      expect(CommunicationRules.validateTitle('abc'), isNull);
      expect(CommunicationRules.validateTitle('a' * 81), isNotNull);
    });
  });

  group('conversation workflow', () {
    test('only members send, and only while open', () {
      expect(CommunicationRules.checkSend(_conv(), 'p1'), isNull);
      expect(CommunicationRules.checkSend(_conv(), 't1'), isNull);
      expect(CommunicationRules.checkSend(_conv(), 'x'), isNotNull);
      expect(
        CommunicationRules.checkSend(
          _conv(status: ConversationStatus.closed),
          'p1',
        ),
        isNotNull,
      );
      expect(
        CommunicationRules.checkSend(
          _conv(status: ConversationStatus.archived),
          't1',
        ),
        isNotNull,
      );
    });

    test('a parent cannot reopen or archive; the teacher can, from closed', () {
      final closed = _conv(status: ConversationStatus.closed);
      expect(CommunicationRules.checkReopen(closed, 'p1'), isNotNull);
      expect(CommunicationRules.checkReopen(closed, 't1'), isNull);
      expect(CommunicationRules.checkReopen(_conv(), 't1'), isNotNull);
      expect(CommunicationRules.checkArchive(closed, 'p1'), isNotNull);
      expect(CommunicationRules.checkArchive(closed, 't1'), isNull);
      expect(CommunicationRules.checkArchive(_conv(), 't1'), isNotNull);
    });

    test('either member closes an open conversation; outsiders cannot', () {
      expect(CommunicationRules.checkClose(_conv(), 'p1'), isNull);
      expect(CommunicationRules.checkClose(_conv(), 't1'), isNull);
      expect(CommunicationRules.checkClose(_conv(), 'x'), isNotNull);
      expect(
        CommunicationRules.checkClose(
          _conv(status: ConversationStatus.closed),
          'p1',
        ),
        isNotNull,
      );
    });

    test('reports need a member, a reason, and are one-off', () {
      expect(CommunicationRules.checkReport(_conv(), 'p1', 'rude'), isNull);
      expect(CommunicationRules.checkReport(_conv(), 'x', 'rude'), isNotNull);
      expect(CommunicationRules.checkReport(_conv(), 'p1', ' '), isNotNull);
      expect(
        CommunicationRules.checkReport(_conv(flagged: true), 'p1', 'rude'),
        isNotNull,
      );
    });

    test('a notification preview names the sender but never the content', () {
      expect(CommunicationRules.previewFor('Meera'), 'New message from Meera');
      expect(CommunicationRules.previewFor('  '), 'New message');
    });

    test('unread counters belong to the right member', () {
      final c = Conversation(
        conversationId: 'x',
        schoolId: 's',
        branchId: 'b',
        academicYearId: 'y',
        classId: 'c',
        sectionId: 'sa',
        studentId: 'st',
        studentName: 'A',
        parentUserId: 'p1',
        parentName: 'P',
        teacherUserId: 't1',
        teacherStaffId: 'tt',
        teacherName: 'T',
        subjectId: 'm',
        subjectName: 'M',
        title: 'abc',
        unreadForParent: 2,
        unreadForTeacher: 5,
      );
      expect(c.unreadFor('p1'), 2);
      expect(c.unreadFor('t1'), 5);
      expect(c.isMember('other'), isFalse);
    });
  });

  group('write plans', () {
    const parent = CommunicationActor(
      userId: 'p1',
      name: 'Parent',
      role: 'PARENT',
    );

    test('ids are deterministic, so a retry hits the same documents', () {
      expect(CommunicationWrites.notificationId('m_1'), 'msg__m_1');
      expect(
        CommunicationWrites.eventId('cv_1', 2),
        CommunicationWrites.eventId('cv_1', 2),
      );
      expect(
        CommunicationWrites.eventId('cv_1', 2),
        isNot(CommunicationWrites.eventId('cv_1', 3)),
      );
    });

    test(
      'a message notification carries the sender, never the message text',
      () {
        final n = CommunicationWrites.notification(
          c: _conv(),
          messageId: 'm_1',
          recipientUserId: 't1',
          actor: parent,
        );
        expect(n['recipientUserId'], 't1');
        expect(n['type'], 'MESSAGE_RECEIVED');
        expect(n['readAt'], isNull);
        expect(n.toString(), isNot(contains('secret text')));
        expect(n['body'].toString(), contains('Parent'));
      },
    );

    test('a message records its true sender', () {
      final m = CommunicationWrites.message(
        c: _conv(),
        body: 'hello',
        attachments: const [],
        actor: parent,
      );
      expect(m['senderUserId'], 'p1');
      expect(m['senderRole'], 'PARENT');
      expect(m['body'], 'hello');
    });
  });

  group('categories, preferences and navigation', () {
    test('types map to categories; unknown ones are administrative', () {
      expect(
        NotificationCategory.forType('MESSAGE_RECEIVED'),
        NotificationCategory.messages,
      );
      expect(
        NotificationCategory.forType('HOMEWORK_GRADED'),
        NotificationCategory.homework,
      );
      expect(
        NotificationCategory.forType('RESULT_PUBLISHED'),
        NotificationCategory.results,
      );
      expect(
        NotificationCategory.forType('LEAVE_APPROVED'),
        NotificationCategory.leave,
      );
      expect(
        NotificationCategory.forType('SUBSTITUTION_ASSIGNED'),
        NotificationCategory.timetable,
      );
      expect(
        NotificationCategory.forType('SOMETHING_NEW'),
        NotificationCategory.administrative,
      );
    });

    test('payment, fee, attendance and holiday notices have a category', () {
      expect(
        NotificationCategory.forType('PAYMENT_RECORDED'),
        NotificationCategory.fees,
      );
      expect(
        NotificationCategory.forType('FEE_DUE_REMINDER'),
        NotificationCategory.fees,
      );
      expect(
        NotificationCategory.forType('ATTENDANCE_ABSENT'),
        NotificationCategory.attendance,
      );
      expect(
        NotificationCategory.forType('HOLIDAY_ADDED'),
        NotificationCategory.announcement,
      );
    });

    test('muting hides a category; administrative cannot be muted', () {
      var p = const NotificationPreferences();
      p = p.toggled(NotificationCategory.homework, mute: true);
      expect(p.shows(NotificationCategory.homework), isFalse);
      expect(p.shows(NotificationCategory.results), isTrue);
      p = p.toggled(NotificationCategory.administrative, mute: true);
      expect(p.shows(NotificationCategory.administrative), isTrue);
      // A tampered stored value cannot hide a critical category either.
      final loaded = NotificationPreferences.fromMap({
        'mutedCategories': ['ADMINISTRATIVE', 'HOMEWORK'],
      });
      expect(loaded.shows(NotificationCategory.administrative), isTrue);
      expect(loaded.shows(NotificationCategory.homework), isFalse);
      expect(p.toMap()['pushEnabled'], isTrue);
    });

    test('routes are the normal role-appropriate screens', () {
      expect(
        NotificationNavigator.routeFor(
          FeedItem(
            id: 'n',
            source: FeedSource.targeted,
            branchId: 'b',
            type: 'MESSAGE_RECEIVED',
            title: 't',
            conversationId: 'cv_9',
          ),
          UserRole.parent,
        ),
        '/messages/cv_9?branchId=b',
      );
      expect(
        NotificationNavigator.routeFor(
          _item('HOMEWORK_PUBLISHED', ref: 'h1'),
          UserRole.parent,
        ),
        '/my-homework',
      );
      expect(
        NotificationNavigator.routeFor(
          _item('SUBSTITUTION_ASSIGNED'),
          UserRole.teacher,
        ),
        '/my-timetable',
      );
      expect(
        NotificationNavigator.routeFor(
          _item('SOMETHING_NEW'),
          UserRole.teacher,
        ),
        isNull,
      );
    });

    test(
      'a stored target never leaves the app: ids are path segments only',
      () {
        final r = NotificationNavigator.routeFor(
          FeedItem(
            id: 'n',
            source: FeedSource.targeted,
            branchId: 'b',
            type: 'MESSAGE_RECEIVED',
            title: 't',
            conversationId: 'cv_9',
          ),
          UserRole.teacher,
        )!;
        expect(r.startsWith('/messages/'), isTrue);
        expect(r.contains('://'), isFalse);
      },
    );

    test('expired items are hidden by the feed', () {
      final item = FeedItem(
        id: 'n',
        source: FeedSource.shared,
        branchId: 'b',
        type: 'ANNOUNCEMENT_PUBLISHED',
        title: 't',
        expiresAt: DateTime(2026, 1, 1),
      );
      expect(item.isExpired(DateTime(2026, 6, 1)), isTrue);
      expect(item.isExpired(DateTime(2025, 12, 31)), isFalse);
    });
  });
}
