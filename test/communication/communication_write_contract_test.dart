import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/communication/data/communication_writes.dart';
import 'package:eazy_school_360/features/communication/domain/communication_repository.dart';
import 'package:eazy_school_360/features/communication/domain/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents the Dart communication code writes to
/// `firestore-tests/fixtures/communication-write-plans.json`;
/// `communication-contract.test.mjs` replays them through the real rules.
const _school = '__SCHOOL__';
const _parent = CommunicationActor(
  userId: 'cc-p1',
  name: 'Parent',
  role: 'PARENT',
);
const _teacher = CommunicationActor(
  userId: 'cc-t1',
  name: 'Teacher',
  role: 'TEACHER',
);

Object? _encode(Object? v) {
  if (v is FieldValue) return {r'$serverTimestamp': true};
  if (v is Timestamp) return {r'$time': v.toDate().toUtc().toIso8601String()};
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _encode(e.value)};
  }
  if (v is List) return [for (final e in v) _encode(e)];
  return v;
}

class _Batch {
  final String as;
  final String label;
  final List<Map<String, Object?>> ops = [];

  _Batch(this.as, this.label);

  void set(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'set', 'path': path, 'data': _encode(data)});
  void update(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'update', 'path': path, 'data': _encode(data)});

  Map<String, Object?> toJson() => {'as': as, 'label': label, 'ops': ops};
}

void main() {
  test('exports the communication write plan', () {
    Conversation conv({int count = 1, int unreadP = 0, int unreadT = 1}) =>
        Conversation(
          conversationId: 'cv_1',
          schoolId: _school,
          branchId: 'north',
          academicYearId: 'y1',
          classId: 'c5',
          sectionId: 'sa',
          studentId: 'cc-s1',
          studentName: 'Anil',
          parentUserId: 'cc-p1',
          parentName: 'Parent',
          teacherUserId: 'cc-t1',
          teacherStaffId: 'st1',
          teacherName: 'Teacher',
          subjectId: 'math',
          subjectName: 'Maths',
          title: 'Homework help',
          messageCount: count,
          unreadForParent: unreadP,
          unreadForTeacher: unreadT,
        );
    final c = conv();
    const base = 'conversations/cv_1';
    final batches = <_Batch>[];

    final start = _Batch('cc-p1', 'parent starts a conversation');
    start.set(
      '$base/messages/m_1',
      CommunicationWrites.message(
        c: c,
        body: 'Could you explain question 4?',
        attachments: const [],
        actor: _parent,
      ),
    );
    start.set(
      base,
      CommunicationWrites.conversationCreate(
        c: c,
        messageId: 'm_1',
        uid: 'cc-p1',
      ),
    );
    start.set(
      'conversationEvents/${CommunicationWrites.eventId('cv_1', 1)}',
      CommunicationWrites.event(
        c: c,
        revision: 1,
        event: 'OPENED',
        toStatus: ConversationStatus.open,
        actor: _parent,
      ),
    );
    start.set(
      'notifications/${CommunicationWrites.notificationId('m_1')}',
      CommunicationWrites.notification(
        c: c,
        messageId: 'm_1',
        recipientUserId: 'cc-t1',
        actor: _parent,
      ),
    );
    batches.add(start);

    final read = _Batch('cc-t1', 'teacher reads (clears own counter)');
    read.update(base, CommunicationWrites.markRead(c: c, uid: 'cc-t1'));
    batches.add(read);

    final reply = _Batch('cc-t1', 'teacher replies');
    final afterRead = conv(unreadT: 0);
    reply.set(
      '$base/messages/m_2',
      CommunicationWrites.message(
        c: afterRead,
        body: 'Of course — see page 12.',
        attachments: const [],
        actor: _teacher,
      ),
    );
    reply.update(
      base,
      CommunicationWrites.conversationAfterMessage(
        c: afterRead,
        messageId: 'm_2',
        uid: 'cc-t1',
      ),
    );
    reply.set(
      'notifications/${CommunicationWrites.notificationId('m_2')}',
      CommunicationWrites.notification(
        c: afterRead,
        messageId: 'm_2',
        recipientUserId: 'cc-p1',
        actor: _teacher,
      ),
    );
    batches.add(reply);

    final c2 = conv(count: 2, unreadP: 1, unreadT: 0);
    final parentRead = _Batch('cc-p1', 'parent reads');
    parentRead.update(base, CommunicationWrites.markRead(c: c2, uid: 'cc-p1'));
    batches.add(parentRead);

    final c3 = conv(count: 2, unreadP: 0, unreadT: 0);
    final parentSend = _Batch('cc-p1', 'parent replies');
    parentSend.set(
      '$base/messages/m_3',
      CommunicationWrites.message(
        c: c3,
        body: 'Thank you!',
        attachments: const [],
        actor: _parent,
      ),
    );
    parentSend.update(
      base,
      CommunicationWrites.conversationAfterMessage(
        c: c3,
        messageId: 'm_3',
        uid: 'cc-p1',
      ),
    );
    parentSend.set(
      'notifications/${CommunicationWrites.notificationId('m_3')}',
      CommunicationWrites.notification(
        c: c3,
        messageId: 'm_3',
        recipientUserId: 'cc-t1',
        actor: _parent,
      ),
    );
    batches.add(parentSend);

    _Batch status(
      String as,
      CommunicationActor actor,
      String label,
      int rev,
      String event,
      ConversationStatus to,
    ) {
      final b = _Batch(as, label);
      b.update(
        base,
        CommunicationWrites.statusChange(
          to: to,
          event: event,
          revision: rev,
          uid: as,
        ),
      );
      b.set(
        'conversationEvents/${CommunicationWrites.eventId('cv_1', rev)}',
        CommunicationWrites.event(
          c: c3,
          revision: rev,
          event: event,
          toStatus: to,
          actor: actor,
        ),
      );
      return b;
    }

    batches.add(
      status(
        'cc-p1',
        _parent,
        'parent closes',
        2,
        'CLOSED',
        ConversationStatus.closed,
      ),
    );
    batches.add(
      status(
        'cc-t1',
        _teacher,
        'teacher reopens',
        3,
        'REOPENED',
        ConversationStatus.open,
      ),
    );
    final report = _Batch('cc-p1', 'parent reports');
    report.update(
      base,
      CommunicationWrites.report(
        reason: 'Inappropriate tone',
        revision: 4,
        uid: 'cc-p1',
      ),
    );
    report.set(
      'conversationEvents/${CommunicationWrites.eventId('cv_1', 4)}',
      CommunicationWrites.event(
        c: c3,
        revision: 4,
        event: 'REPORTED',
        toStatus: ConversationStatus.open,
        actor: _parent,
        note: 'Inappropriate tone',
      ),
    );
    batches.add(report);
    batches.add(
      status(
        'cc-t1',
        _teacher,
        'teacher closes',
        5,
        'CLOSED',
        ConversationStatus.closed,
      ),
    );
    batches.add(
      status(
        'cc-t1',
        _teacher,
        'teacher archives',
        6,
        'ARCHIVED',
        ConversationStatus.archived,
      ),
    );

    final contact = _Batch('cc-t1', 'teacher opts in to parent messages');
    contact.set('messageContacts/st1', {
      'schoolId': _school,
      'branchId': 'north',
      'staffId': 'st1',
      'userId': 'cc-t1',
      'name': 'Teacher',
      'enabled': true,
      'sectionKeys': ['y1__c5__sa'],
      'scopes': ['y1__c5__sa__math'],
      'subjectNames': {'y1__c5__sa__math': 'Maths'},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final out = File('firestore-tests/fixtures/communication-write-plans.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scenarios': [
          {
            'name': 'teacher opt-in',
            'batches': [contact.toJson()],
          },
          {
            'name': 'conversation lifecycle',
            'batches': [for (final b in batches) b.toJson()],
          },
        ],
      }),
    );
    expect(batches.length, greaterThan(8));
  });
}
