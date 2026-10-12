import 'dart:async';

import 'package:eazy_school_360/features/communication/domain/communication_repository.dart';
import 'package:eazy_school_360/features/communication/domain/communication_rules.dart';
import 'package:eazy_school_360/features/communication/domain/conversation.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_preferences.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_repository.dart';

/// Notifications keyed by recipient, so a fake can prove one user's marks
/// never touch another's.
class FakeNotificationRepository implements NotificationRepository {
  final Map<String, List<FeedItem>> byUser = {};
  final Map<String, Set<String>> readIds = {};
  final Map<String, NotificationPreferences> prefs = {};
  final List<String> calls = [];
  final Map<String, Set<String>> devices = {};
  int watchers = 0;
  int cancelled = 0;
  Object? failMarkRead;

  FakeNotificationRepository([Map<String, List<FeedItem>>? seed]) {
    if (seed != null) byUser.addAll(seed);
  }

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<FeedItem>> watchTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  }) {
    late StreamController<List<FeedItem>> c;
    StreamSubscription<void>? sub;
    List<FeedItem> snapshot() => [
      for (final i in (byUser[userId] ?? const <FeedItem>[]))
        if (i.branchId == branchId) i,
    ].take(limit).toList();
    c = StreamController<List<FeedItem>>(
      onListen: () {
        watchers++;
        c.add(snapshot());
        sub = _changes.stream.listen((_) => c.add(snapshot()));
      },
      onCancel: () {
        cancelled++;
        return sub?.cancel();
      },
    );
    return c.stream;
  }

  @override
  Future<int> countUnreadTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
  }) async => (byUser[userId] ?? []).where((i) => !i.read).length;

  @override
  Future<void> markRead({
    required String schoolId,
    required String branchId,
    required String notificationId,
  }) async {
    calls.add('markRead:$notificationId');
    if (failMarkRead != null) throw failMarkRead!;
    for (final list in byUser.values) {
      final i = list.indexWhere((n) => n.id == notificationId);
      if (i >= 0) list[i] = list[i].copyWith(read: true);
    }
    _changes.add(null);
  }

  /// The signed-in user is recorded so only their notifications change.
  String? actingUser;

  @override
  Future<int> markAllRead({
    required String schoolId,
    required String branchId,
    required String userId,
  }) async {
    calls.add('markAll:$userId');
    var n = 0;
    final list = byUser[userId] ?? [];
    for (var i = 0; i < list.length; i++) {
      if (!list[i].read && list[i].branchId == branchId) {
        list[i] = list[i].copyWith(read: true);
        n++;
      }
    }
    _changes.add(null);
    return n;
  }

  @override
  Future<List<FeedItem>> fetchReviewerNotices({
    required String schoolId,
    required String branchId,
    int limit = 50,
  }) async => const [];

  @override
  Future<Set<String>> fetchReadIds(String userId) async => {
    ...?readIds[userId],
  };

  @override
  Future<void> addReadIds(String userId, Set<String> ids) async {
    calls.add('addReadIds:${ids.length}');
    readIds.putIfAbsent(userId, () => {}).addAll(ids);
  }

  @override
  Future<NotificationPreferences> fetchPreferences(String userId) async =>
      prefs[userId] ?? const NotificationPreferences();

  @override
  Future<void> savePreferences(String userId, NotificationPreferences p) async {
    calls.add('savePrefs');
    prefs[userId] = p;
  }

  @override
  Future<void> saveDevice({
    required String userId,
    required String token,
    required String platform,
  }) async => (devices[userId] ??= {}).add(token);

  @override
  Future<void> removeDevice({
    required String userId,
    required String token,
  }) async => devices[userId]?.remove(token);
}

/// An in-memory conversation store that applies the same rules the security
/// rules do, and keeps one message per id (retries do not duplicate).
class FakeCommunicationRepository implements CommunicationRepository {
  final Map<String, Conversation> conversations = {};
  final Map<String, List<Message>> messages = {};
  final Map<String, List<ConversationEvent>> events = {};
  final Map<String, MessageContact> contacts = {};
  final List<String> sentNotifications = [];
  int sendAttempts = 0;

  /// Number of upcoming `send` calls that fail before reaching the store.
  int failSends = 0;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<MessageContact>> fetchContactsForSection({
    required String schoolId,
    required String branchId,
    required String sectionKey,
  }) async => [
    for (final c in contacts.values)
      if (c.enabled && c.sectionKeys.contains(sectionKey)) c,
  ];

  @override
  Future<MessageContact?> fetchOwnContact({
    required String schoolId,
    required String branchId,
    required String staffId,
  }) async => contacts[staffId];

  @override
  Future<void> saveOwnContact({
    required String schoolId,
    required String branchId,
    required MessageContact contact,
  }) async => contacts[contact.staffId] = contact;

  @override
  Stream<List<Conversation>> watchMine({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  }) async* {
    List<Conversation> snap() => [
      for (final c in conversations.values)
        if (c.branchId == branchId && c.isMember(userId)) c,
    ].take(limit).toList();
    yield snap();
    await for (final _ in _changes.stream) {
      yield snap();
    }
  }

  @override
  Future<List<Conversation>> fetchReported({
    required String schoolId,
    required String branchId,
  }) async => [
    for (final c in conversations.values)
      if (c.flagged && c.branchId == branchId) c,
  ];

  @override
  Stream<Conversation?> watch(
    String schoolId,
    String branchId,
    String id,
  ) async* {
    yield conversations[id];
    await for (final _ in _changes.stream) {
      yield conversations[id];
    }
  }

  @override
  Stream<List<Message>> watchMessages({
    required String schoolId,
    required String branchId,
    required String conversationId,
    required int limit,
  }) async* {
    yield List.of(messages[conversationId] ?? const []);
    await for (final _ in _changes.stream) {
      yield List.of(messages[conversationId] ?? const []);
    }
  }

  @override
  Future<List<ConversationEvent>> fetchEvents(
    String schoolId,
    String branchId,
    String conversationId,
  ) async => events[conversationId] ?? const [];

  void _event(Conversation c, String event, ConversationStatus to, String by) {
    events
        .putIfAbsent(c.conversationId, () => [])
        .add(
          ConversationEvent(
            revision: c.revision + 1,
            event: event,
            toStatus: to.wireValue,
            actorName: by,
            at: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> start({
    required Conversation conversation,
    required String messageId,
    required String body,
    required CommunicationActor actor,
  }) async {
    if (conversations.containsKey(conversation.conversationId)) return;
    final problem =
        CommunicationRules.validateMessage(body) ??
        CommunicationRules.validateTitle(conversation.title);
    if (problem != null) throw StateError(problem);
    messages[conversation.conversationId] = [
      Message(
        messageId: messageId,
        conversationId: conversation.conversationId,
        senderUserId: actor.userId,
        senderName: actor.name,
        senderRole: actor.role,
        body: body,
        createdAt: DateTime.now(),
      ),
    ];
    conversations[conversation.conversationId] = Conversation(
      conversationId: conversation.conversationId,
      schoolId: conversation.schoolId,
      branchId: conversation.branchId,
      academicYearId: conversation.academicYearId,
      classId: conversation.classId,
      sectionId: conversation.sectionId,
      studentId: conversation.studentId,
      studentName: conversation.studentName,
      parentUserId: conversation.parentUserId,
      parentName: conversation.parentName,
      teacherUserId: conversation.teacherUserId,
      teacherStaffId: conversation.teacherStaffId,
      teacherName: conversation.teacherName,
      subjectId: conversation.subjectId,
      subjectName: conversation.subjectName,
      title: conversation.title,
      messageCount: 1,
      lastMessageId: messageId,
      lastMessageAt: DateTime.now(),
      unreadForTeacher: 1,
    );
    sentNotifications.add('msg__$messageId');
    _changes.add(null);
  }

  @override
  Future<void> send({
    required Conversation conversation,
    required String messageId,
    required String body,
    required List<FileAttachment> attachments,
    required CommunicationActor actor,
  }) async {
    sendAttempts++;
    if (failSends > 0) {
      failSends--;
      throw StateError('network down');
    }
    final c = conversations[conversation.conversationId]!;
    final denied = CommunicationRules.checkSend(c, actor.userId);
    if (denied != null) throw StateError(denied);
    final problem = CommunicationRules.validateMessage(
      body,
      attachments: attachments,
    );
    if (problem != null) throw StateError(problem);
    final list = messages.putIfAbsent(c.conversationId, () => []);
    if (list.any((m) => m.messageId == messageId)) return; // idempotent
    list.add(
      Message(
        messageId: messageId,
        conversationId: c.conversationId,
        senderUserId: actor.userId,
        senderName: actor.name,
        senderRole: actor.role,
        body: body,
        attachments: attachments,
        createdAt: DateTime.now(),
      ),
    );
    final fromParent = c.isParent(actor.userId);
    conversations[c.conversationId] = _copy(
      c,
      messageCount: c.messageCount + 1,
      lastMessageId: messageId,
      unreadForParent: fromParent ? c.unreadForParent : c.unreadForParent + 1,
      unreadForTeacher: fromParent
          ? c.unreadForTeacher + 1
          : c.unreadForTeacher,
    );
    sentNotifications.add('msg__$messageId');
    _changes.add(null);
  }

  Conversation _copy(
    Conversation c, {
    ConversationStatus? status,
    int? revision,
    int? messageCount,
    String? lastMessageId,
    int? unreadForParent,
    int? unreadForTeacher,
    bool? flagged,
    String? flagReason,
  }) => Conversation(
    conversationId: c.conversationId,
    schoolId: c.schoolId,
    branchId: c.branchId,
    academicYearId: c.academicYearId,
    classId: c.classId,
    sectionId: c.sectionId,
    studentId: c.studentId,
    studentName: c.studentName,
    parentUserId: c.parentUserId,
    parentName: c.parentName,
    teacherUserId: c.teacherUserId,
    teacherStaffId: c.teacherStaffId,
    teacherName: c.teacherName,
    subjectId: c.subjectId,
    subjectName: c.subjectName,
    title: c.title,
    status: status ?? c.status,
    revision: revision ?? c.revision,
    messageCount: messageCount ?? c.messageCount,
    lastMessageId: lastMessageId ?? c.lastMessageId,
    lastMessageAt: DateTime.now(),
    unreadForParent: unreadForParent ?? c.unreadForParent,
    unreadForTeacher: unreadForTeacher ?? c.unreadForTeacher,
    flagged: flagged ?? c.flagged,
    flagReason: flagReason ?? c.flagReason,
  );

  @override
  Future<void> markRead({
    required Conversation conversation,
    required CommunicationActor actor,
  }) async {
    final c = conversations[conversation.conversationId]!;
    if (!c.isMember(actor.userId)) throw StateError('not a member');
    conversations[c.conversationId] = c.isParent(actor.userId)
        ? _copy(c, unreadForParent: 0)
        : _copy(c, unreadForTeacher: 0);
    _changes.add(null);
  }

  Future<void> _status(
    Conversation conversation,
    CommunicationActor actor,
    String? denied,
    ConversationStatus to,
    String event,
  ) async {
    if (denied != null) throw StateError(denied);
    final c = conversations[conversation.conversationId]!;
    _event(c, event, to, actor.name);
    conversations[c.conversationId] = _copy(
      c,
      status: to,
      revision: c.revision + 1,
    );
    _changes.add(null);
  }

  @override
  Future<void> close({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation,
    actor,
    CommunicationRules.checkClose(conversation, actor.userId),
    ConversationStatus.closed,
    'CLOSED',
  );

  @override
  Future<void> reopen({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation,
    actor,
    CommunicationRules.checkReopen(conversation, actor.userId),
    ConversationStatus.open,
    'REOPENED',
  );

  @override
  Future<void> archive({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation,
    actor,
    CommunicationRules.checkArchive(conversation, actor.userId),
    ConversationStatus.archived,
    'ARCHIVED',
  );

  @override
  Future<void> report({
    required Conversation conversation,
    required String reason,
    required CommunicationActor actor,
  }) async {
    final denied = CommunicationRules.checkReport(
      conversation,
      actor.userId,
      reason,
    );
    if (denied != null) throw StateError(denied);
    final c = conversations[conversation.conversationId]!;
    _event(c, 'REPORTED', c.status, actor.name);
    conversations[c.conversationId] = _copy(
      c,
      flagged: true,
      flagReason: reason,
      revision: c.revision + 1,
    );
    _changes.add(null);
  }
}
