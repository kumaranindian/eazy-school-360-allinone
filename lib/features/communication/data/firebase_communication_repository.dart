import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../homework/domain/file_attachment.dart';
import '../domain/communication_repository.dart';
import '../domain/communication_rules.dart';
import '../domain/conversation.dart';
import 'communication_writes.dart';

class FirebaseCommunicationRepository implements CommunicationRepository {
  final FirebaseFirestore _firestore;

  FirebaseCommunicationRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _branch(String s, String b) =>
      _firestore
          .collection(FirestoreFields.schoolsCollection)
          .doc(s)
          .collection(FirestoreFields.branchesCollection)
          .doc(b);

  CollectionReference<Map<String, dynamic>> _conversations(
    String s,
    String b,
  ) => _branch(s, b).collection(FirestoreFields.conversationsCollection);

  CollectionReference<Map<String, dynamic>> _messages(
    String s,
    String b,
    String id,
  ) => _conversations(
    s,
    b,
  ).doc(id).collection(FirestoreFields.conversationMessagesCollection);

  CollectionReference<Map<String, dynamic>> _events(String s, String b) =>
      _branch(s, b).collection(FirestoreFields.conversationEventsCollection);

  CollectionReference<Map<String, dynamic>> _notifications(
    String s,
    String b,
  ) => _branch(s, b).collection(FirestoreFields.notificationsCollection);

  CollectionReference<Map<String, dynamic>> _contacts(String s, String b) =>
      _branch(s, b).collection('messageContacts');

  @override
  Future<List<MessageContact>> fetchContactsForSection({
    required String schoolId,
    required String branchId,
    required String sectionKey,
  }) async {
    try {
      final snap = await _contacts(schoolId, branchId)
          .where('enabled', isEqualTo: true)
          .where('sectionKeys', arrayContains: sectionKey)
          .get();
      return [
        for (final d in snap.docs) MessageContact.fromFirestore(d.data()),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<MessageContact?> fetchOwnContact({
    required String schoolId,
    required String branchId,
    required String staffId,
  }) async {
    try {
      final snap = await _contacts(schoolId, branchId).doc(staffId).get();
      return snap.exists ? MessageContact.fromFirestore(snap.data()!) : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> saveOwnContact({
    required String schoolId,
    required String branchId,
    required MessageContact contact,
  }) async {
    try {
      await _contacts(schoolId, branchId)
          .doc(contact.staffId)
          .set(contact.toMap(schoolId: schoolId, branchId: branchId));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Conversation>> watchMine({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  }) => _conversations(schoolId, branchId)
      .where('participants', arrayContains: userId)
      .orderBy('lastMessageAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) Conversation.fromFirestore(d.data(), d.id),
        ],
      );

  @override
  Future<List<Conversation>> fetchReported({
    required String schoolId,
    required String branchId,
  }) async {
    try {
      final snap = await _conversations(
        schoolId,
        branchId,
      ).where('flagged', isEqualTo: true).limit(100).get();
      return [
        for (final d in snap.docs) Conversation.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Conversation?> watch(String schoolId, String branchId, String id) =>
      _conversations(schoolId, branchId)
          .doc(id)
          .snapshots()
          .map(
            (s) =>
                s.exists ? Conversation.fromFirestore(s.data()!, s.id) : null,
          );

  @override
  Stream<List<Message>> watchMessages({
    required String schoolId,
    required String branchId,
    required String conversationId,
    required int limit,
  }) => _messages(schoolId, branchId, conversationId)
      .orderBy(FirestoreFields.createdAt, descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs.reversed)
            Message.fromFirestore(d.data(), d.id),
        ],
      );

  @override
  Future<List<ConversationEvent>> fetchEvents(
    String schoolId,
    String branchId,
    String conversationId,
  ) async {
    try {
      final snap = await _events(
        schoolId,
        branchId,
      ).where('conversationId', isEqualTo: conversationId).get();
      final list = [
        for (final d in snap.docs)
          ConversationEvent(
            revision: (d.data()['revision'] as num).toInt(),
            event: d.data()['event'] as String,
            toStatus: d.data()['toStatus'] as String,
            actorName: d.data()['actorName'] as String? ?? '',
            note: d.data()['note'] as String?,
            at: (d.data()['at'] as Timestamp?)?.toDate(),
          ),
      ]..sort((a, b) => a.revision.compareTo(b.revision));
      return list;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> start({
    required Conversation conversation,
    required String messageId,
    required String body,
    required CommunicationActor actor,
  }) async {
    final t = CommunicationRules.validateTitle(conversation.title);
    if (t != null) throw ValidationFailure(t);
    final m = CommunicationRules.validateMessage(body);
    if (m != null) throw ValidationFailure(m);
    final c = conversation;
    final convRef = _conversations(
      c.schoolId,
      c.branchId,
    ).doc(c.conversationId);
    final batch = _firestore.batch();
    batch.set(
      _messages(c.schoolId, c.branchId, c.conversationId).doc(messageId),
      CommunicationWrites.message(
        c: c,
        body: body,
        attachments: const [],
        actor: actor,
      ),
    );
    batch.set(
      convRef,
      CommunicationWrites.conversationCreate(
        c: c,
        messageId: messageId,
        uid: actor.userId,
      ),
    );
    batch.set(
      _events(
        c.schoolId,
        c.branchId,
      ).doc(CommunicationWrites.eventId(c.conversationId, 1)),
      CommunicationWrites.event(
        c: c,
        revision: 1,
        event: 'OPENED',
        toStatus: ConversationStatus.open,
        actor: actor,
      ),
    );
    batch.set(
      _notifications(
        c.schoolId,
        c.branchId,
      ).doc(CommunicationWrites.notificationId(messageId)),
      CommunicationWrites.notification(
        c: c,
        messageId: messageId,
        recipientUserId: c.teacherUserId,
        actor: actor,
      ),
    );
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      // A retry of a commit that actually succeeded is not an error.
      if (await _exists(
        _messages(c.schoolId, c.branchId, c.conversationId).doc(messageId),
      )) {
        return;
      }
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<bool> _exists(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return (await ref.get()).exists;
    } catch (_) {
      return false;
    }
  }

  Future<Conversation> _fresh(Conversation c) async {
    final snap = await _conversations(
      c.schoolId,
      c.branchId,
    ).doc(c.conversationId).get();
    if (!snap.exists) {
      throw const NotFoundFailure('This conversation is not available.');
    }
    return Conversation.fromFirestore(snap.data()!, snap.id);
  }

  @override
  Future<void> send({
    required Conversation conversation,
    required String messageId,
    required String body,
    required List<FileAttachment> attachments,
    required CommunicationActor actor,
  }) async {
    final v = CommunicationRules.validateMessage(
      body,
      attachments: attachments,
    );
    if (v != null) throw ValidationFailure(v);
    final msgRef = _messages(
      conversation.schoolId,
      conversation.branchId,
      conversation.conversationId,
    ).doc(messageId);
    try {
      // Already written by an earlier attempt of this same send: done.
      if (await _exists(msgRef)) return;
      final c = await _fresh(conversation);
      final problem = CommunicationRules.checkSend(c, actor.userId);
      if (problem != null) throw ConflictFailure(problem);
      final other = c.isParent(actor.userId) ? c.teacherUserId : c.parentUserId;
      final batch = _firestore.batch();
      batch.set(
        msgRef,
        CommunicationWrites.message(
          c: c,
          body: body,
          attachments: attachments,
          actor: actor,
        ),
      );
      batch.update(
        _conversations(c.schoolId, c.branchId).doc(c.conversationId),
        CommunicationWrites.conversationAfterMessage(
          c: c,
          messageId: messageId,
          uid: actor.userId,
        ),
      );
      batch.set(
        _notifications(
          c.schoolId,
          c.branchId,
        ).doc(CommunicationWrites.notificationId(messageId)),
        CommunicationWrites.notification(
          c: c,
          messageId: messageId,
          recipientUserId: other,
          actor: actor,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      if (await _exists(msgRef)) return;
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> markRead({
    required Conversation conversation,
    required CommunicationActor actor,
  }) async {
    final c = conversation;
    if (c.unreadFor(actor.userId) == 0) return;
    try {
      await _conversations(c.schoolId, c.branchId)
          .doc(c.conversationId)
          .update(CommunicationWrites.markRead(c: c, uid: actor.userId));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<void> _status({
    required Conversation conversation,
    required CommunicationActor actor,
    required String? Function(Conversation fresh) check,
    required ConversationStatus to,
    required String event,
  }) async {
    try {
      final c = await _fresh(conversation);
      final problem = check(c);
      if (problem != null) throw ConflictFailure(problem);
      final rev = c.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        _conversations(c.schoolId, c.branchId).doc(c.conversationId),
        CommunicationWrites.statusChange(
          to: to,
          event: event,
          revision: rev,
          uid: actor.userId,
        ),
      );
      batch.set(
        _events(
          c.schoolId,
          c.branchId,
        ).doc(CommunicationWrites.eventId(c.conversationId, rev)),
        CommunicationWrites.event(
          c: c,
          revision: rev,
          event: event,
          toStatus: to,
          actor: actor,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> close({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation: conversation,
    actor: actor,
    check: (c) => CommunicationRules.checkClose(c, actor.userId),
    to: ConversationStatus.closed,
    event: 'CLOSED',
  );

  @override
  Future<void> reopen({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation: conversation,
    actor: actor,
    check: (c) => CommunicationRules.checkReopen(c, actor.userId),
    to: ConversationStatus.open,
    event: 'REOPENED',
  );

  @override
  Future<void> archive({
    required Conversation conversation,
    required CommunicationActor actor,
  }) => _status(
    conversation: conversation,
    actor: actor,
    check: (c) => CommunicationRules.checkArchive(c, actor.userId),
    to: ConversationStatus.archived,
    event: 'ARCHIVED',
  );

  @override
  Future<void> report({
    required Conversation conversation,
    required String reason,
    required CommunicationActor actor,
  }) async {
    try {
      final c = await _fresh(conversation);
      final problem = CommunicationRules.checkReport(c, actor.userId, reason);
      if (problem != null) throw ConflictFailure(problem);
      final rev = c.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        _conversations(c.schoolId, c.branchId).doc(c.conversationId),
        CommunicationWrites.report(
          reason: reason,
          revision: rev,
          uid: actor.userId,
        ),
      );
      batch.set(
        _events(
          c.schoolId,
          c.branchId,
        ).doc(CommunicationWrites.eventId(c.conversationId, rev)),
        CommunicationWrites.event(
          c: c,
          revision: rev,
          event: 'REPORTED',
          toStatus: c.status,
          actor: actor,
          note: reason,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
