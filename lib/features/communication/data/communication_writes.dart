import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../homework/domain/file_attachment.dart';
import '../domain/communication_repository.dart';
import '../domain/communication_rules.dart';
import '../domain/conversation.dart';

/// Every document the communication workflow writes, as a pure function (a
/// contract test replays them through the real rules).
abstract final class CommunicationWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  static Map<String, dynamic> message({
    required Conversation c,
    required String body,
    required List<FileAttachment> attachments,
    required CommunicationActor actor,
  }) => {
    FirestoreFields.schoolId: c.schoolId,
    FirestoreFields.branchId: c.branchId,
    'conversationId': c.conversationId,
    'senderUserId': actor.userId,
    'senderName': actor.name,
    'senderRole': actor.role,
    'body': body.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> conversationCreate({
    required Conversation c,
    required String messageId,
    required String uid,
  }) => {
    FirestoreFields.schoolId: c.schoolId,
    FirestoreFields.branchId: c.branchId,
    'academicYearId': c.academicYearId,
    'classId': c.classId,
    'sectionId': c.sectionId,
    'studentId': c.studentId,
    'studentName': c.studentName,
    'parentUserId': c.parentUserId,
    'parentName': c.parentName,
    'teacherUserId': c.teacherUserId,
    'teacherStaffId': c.teacherStaffId,
    'teacherName': c.teacherName,
    'subjectId': c.subjectId,
    'subjectName': c.subjectName,
    'title': c.title.trim(),
    'participants': [c.parentUserId, c.teacherUserId],
    FirestoreFields.status: ConversationStatus.open.wireValue,
    'revision': 1,
    'lastEvent': 'OPENED',
    'messageCount': 1,
    'lastMessageId': messageId,
    'lastMessageAt': FieldValue.serverTimestamp(),
    'unreadForParent': 0,
    'unreadForTeacher': 1,
    'lastReadParentAt': FieldValue.serverTimestamp(),
    'lastReadTeacherAt': null,
    'flagged': false,
    'flagReason': null,
    'flaggedBy': null,
    'flaggedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: uid,
    FirestoreFields.updatedBy: uid,
  };

  /// The conversation's change for a message sent by [actor]: the message
  /// counter, the last-message pointer and the *other* member's unread count.
  static Map<String, dynamic> conversationAfterMessage({
    required Conversation c,
    required String messageId,
    required String uid,
  }) => {
    'messageCount': c.messageCount + 1,
    'lastMessageId': messageId,
    'lastMessageAt': FieldValue.serverTimestamp(),
    if (c.isParent(uid))
      'unreadForTeacher': c.unreadForTeacher + 1
    else
      'unreadForParent': c.unreadForParent + 1,
    ...stamp(uid),
  };

  static Map<String, dynamic> markRead({
    required Conversation c,
    required String uid,
  }) => c.isParent(uid)
      ? {
          'unreadForParent': 0,
          'lastReadParentAt': FieldValue.serverTimestamp(),
          ...stamp(uid),
        }
      : {
          'unreadForTeacher': 0,
          'lastReadTeacherAt': FieldValue.serverTimestamp(),
          ...stamp(uid),
        };

  static Map<String, dynamic> statusChange({
    required ConversationStatus to,
    required String event,
    required int revision,
    required String uid,
  }) => {
    FirestoreFields.status: to.wireValue,
    'revision': revision,
    'lastEvent': event,
    ...stamp(uid),
  };

  static Map<String, dynamic> report({
    required String reason,
    required int revision,
    required String uid,
  }) => {
    'flagged': true,
    'flagReason': reason.trim(),
    'flaggedBy': uid,
    'flaggedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': 'REPORTED',
    ...stamp(uid),
  };

  static String eventId(String conversationId, int revision) =>
      '${conversationId}__$revision';

  static Map<String, dynamic> event({
    required Conversation c,
    required int revision,
    required String event,
    required ConversationStatus toStatus,
    required CommunicationActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: c.schoolId,
    FirestoreFields.branchId: c.branchId,
    'conversationId': c.conversationId,
    'revision': revision,
    'event': event,
    'toStatus': toStatus.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static String notificationId(String messageId) => 'msg__$messageId';

  /// To the other member. Says who wrote, never what.
  static Map<String, dynamic> notification({
    required Conversation c,
    required String messageId,
    required String recipientUserId,
    required CommunicationActor actor,
  }) => {
    FirestoreFields.schoolId: c.schoolId,
    FirestoreFields.branchId: c.branchId,
    'audience': 'USER',
    'recipientUserId': recipientUserId,
    'type': 'MESSAGE_RECEIVED',
    'applicationId': null,
    'conversationId': c.conversationId,
    'messageId': messageId,
    'title': 'New message',
    'body': CommunicationRules.previewFor(actor.name),
    'createdBy': actor.userId,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    'readAt': null,
  };
}
