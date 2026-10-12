import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../homework/domain/file_attachment.dart';

enum ConversationStatus {
  open('OPEN', 'Open'),
  closed('CLOSED', 'Closed'),
  archived('ARCHIVED', 'Archived');

  final String wireValue;
  final String displayName;
  const ConversationStatus(this.wireValue, this.displayName);

  static ConversationStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// One thread between one linked parent and one teacher about one student.
/// [participants] (exactly those two user ids) is the membership: it never
/// changes after creation.
class Conversation {
  final String conversationId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String studentId;
  final String studentName;
  final String parentUserId;
  final String parentName;
  final String teacherUserId;
  final String teacherStaffId;
  final String teacherName;

  /// A subject id, or `CLASS_TEACHER`.
  final String subjectId;
  final String subjectName;
  final String title;
  final ConversationStatus status;
  final int revision;
  final int messageCount;
  final String? lastMessageId;
  final DateTime? lastMessageAt;
  final int unreadForParent;
  final int unreadForTeacher;
  final bool flagged;
  final String? flagReason;
  final DateTime? createdAt;

  const Conversation({
    required this.conversationId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    required this.studentId,
    required this.studentName,
    required this.parentUserId,
    required this.parentName,
    required this.teacherUserId,
    required this.teacherStaffId,
    required this.teacherName,
    required this.subjectId,
    required this.subjectName,
    required this.title,
    this.status = ConversationStatus.open,
    this.revision = 1,
    this.messageCount = 0,
    this.lastMessageId,
    this.lastMessageAt,
    this.unreadForParent = 0,
    this.unreadForTeacher = 0,
    this.flagged = false,
    this.flagReason,
    this.createdAt,
  });

  static String newId() =>
      'cv_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  bool isParent(String userId) => userId == parentUserId;
  bool isMember(String userId) =>
      userId == parentUserId || userId == teacherUserId;

  int unreadFor(String userId) =>
      userId == parentUserId ? unreadForParent : unreadForTeacher;

  String otherName(String userId) =>
      userId == parentUserId ? teacherName : parentName;

  factory Conversation.fromFirestore(Map<String, dynamic> d, String id) =>
      Conversation(
        conversationId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        classId: d['classId'] as String,
        sectionId: d['sectionId'] as String,
        studentId: d['studentId'] as String,
        studentName: d['studentName'] as String? ?? '',
        parentUserId: d['parentUserId'] as String,
        parentName: d['parentName'] as String? ?? '',
        teacherUserId: d['teacherUserId'] as String,
        teacherStaffId: d['teacherStaffId'] as String,
        teacherName: d['teacherName'] as String? ?? '',
        subjectId: d['subjectId'] as String,
        subjectName: d['subjectName'] as String? ?? '',
        title: d['title'] as String? ?? '',
        status: ConversationStatus.fromWireValue(
          d[FirestoreFields.status] as String,
        ),
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
        lastMessageId: d['lastMessageId'] as String?,
        lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
        unreadForParent: (d['unreadForParent'] as num?)?.toInt() ?? 0,
        unreadForTeacher: (d['unreadForTeacher'] as num?)?.toInt() ?? 0,
        flagged: d['flagged'] as bool? ?? false,
        flagReason: d['flagReason'] as String?,
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      );
}

class Message {
  final String messageId;
  final String conversationId;
  final String senderUserId;
  final String senderName;
  final String senderRole;
  final String body;
  final List<FileAttachment> attachments;
  final DateTime? createdAt;

  const Message({
    required this.messageId,
    required this.conversationId,
    required this.senderUserId,
    this.senderName = '',
    this.senderRole = '',
    required this.body,
    this.attachments = const [],
    this.createdAt,
  });

  static String newId() =>
      'm_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  factory Message.fromFirestore(Map<String, dynamic> d, String id) => Message(
    messageId: id,
    conversationId: d['conversationId'] as String? ?? '',
    senderUserId: d['senderUserId'] as String,
    senderName: d['senderName'] as String? ?? '',
    senderRole: d['senderRole'] as String? ?? '',
    body: d['body'] as String? ?? '',
    attachments: [
      for (final a in d['attachments'] as List? ?? [])
        FileAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
    ],
    createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
  );
}

/// An append-only record of a status change or report.
class ConversationEvent {
  final int revision;
  final String event;
  final String toStatus;
  final String actorName;
  final String? note;
  final DateTime? at;

  const ConversationEvent({
    required this.revision,
    required this.event,
    required this.toStatus,
    required this.actorName,
    this.note,
    this.at,
  });
}

/// A teacher's opt-in to parent messages, with where they teach. `scopes` are
/// assignment slot keys (`year__class__section__subject|CLASS_TEACHER`), the
/// same keys the security rules check a conversation against.
class MessageContact {
  final String staffId;
  final String userId;
  final String name;
  final bool enabled;
  final List<String> sectionKeys;
  final List<String> scopes;
  final Map<String, String> subjectNames;

  const MessageContact({
    required this.staffId,
    required this.userId,
    required this.name,
    required this.enabled,
    this.sectionKeys = const [],
    this.scopes = const [],
    this.subjectNames = const {},
  });

  static String sectionKey(String year, String classId, String sectionId) =>
      '${year}__${classId}__$sectionId';

  /// (subjectId or CLASS_TEACHER, label) for the teaching in one section.
  List<(String, String)> subjectsFor(String sectionKey) => [
    for (final s in scopes)
      if (s.startsWith('${sectionKey}__'))
        (
          s.substring(sectionKey.length + 2),
          s.endsWith('__CLASS_TEACHER')
              ? 'Class teacher'
              : (subjectNames[s] ?? s.substring(sectionKey.length + 2)),
        ),
  ];

  factory MessageContact.fromFirestore(Map<String, dynamic> d) =>
      MessageContact(
        staffId: d['staffId'] as String,
        userId: d['userId'] as String,
        name: d['name'] as String? ?? '',
        enabled: d['enabled'] as bool? ?? false,
        sectionKeys: [
          for (final k in d['sectionKeys'] as List? ?? []) k as String,
        ],
        scopes: [for (final k in d['scopes'] as List? ?? []) k as String],
        subjectNames: {
          for (final e in (d['subjectNames'] as Map? ?? {}).entries)
            e.key as String: e.value as String,
        },
      );

  Map<String, dynamic> toMap({
    required String schoolId,
    required String branchId,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'staffId': staffId,
    'userId': userId,
    'name': name,
    'enabled': enabled,
    'sectionKeys': sectionKeys,
    'scopes': scopes,
    'subjectNames': subjectNames,
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
  };
}
