import '../../homework/domain/file_attachment.dart';
import 'conversation.dart';

class CommunicationActor {
  final String userId;
  final String name;
  final String role;

  const CommunicationActor({
    required this.userId,
    required this.name,
    required this.role,
  });
}

abstract class CommunicationRepository {
  /// Teachers who accept parent messages and teach in this section.
  Future<List<MessageContact>> fetchContactsForSection({
    required String schoolId,
    required String branchId,
    required String sectionKey,
  });

  Future<MessageContact?> fetchOwnContact({
    required String schoolId,
    required String branchId,
    required String staffId,
  });

  Future<void> saveOwnContact({
    required String schoolId,
    required String branchId,
    required MessageContact contact,
  });

  /// Conversations the user belongs to, most recently active first. A live
  /// listener bounded by [limit].
  Stream<List<Conversation>> watchMine({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  });

  /// Reported conversations (administrators; the rules grant this read only
  /// for a conversation a member has reported).
  Future<List<Conversation>> fetchReported({
    required String schoolId,
    required String branchId,
  });

  Stream<Conversation?> watch(String schoolId, String branchId, String id);

  /// The newest [limit] messages, oldest first.
  Stream<List<Message>> watchMessages({
    required String schoolId,
    required String branchId,
    required String conversationId,
    required int limit,
  });

  Future<List<ConversationEvent>> fetchEvents(
    String schoolId,
    String branchId,
    String conversationId,
  );

  /// Parent opens a conversation with its first message, one commit.
  /// Idempotent on [conversation].conversationId and [messageId].
  Future<void> start({
    required Conversation conversation,
    required String messageId,
    required String body,
    required CommunicationActor actor,
  });

  /// Idempotent on [messageId]: a retry of a commit that happened returns
  /// quietly.
  Future<void> send({
    required Conversation conversation,
    required String messageId,
    required String body,
    required List<FileAttachment> attachments,
    required CommunicationActor actor,
  });

  Future<void> markRead({
    required Conversation conversation,
    required CommunicationActor actor,
  });

  Future<void> close({
    required Conversation conversation,
    required CommunicationActor actor,
  });

  Future<void> reopen({
    required Conversation conversation,
    required CommunicationActor actor,
  });

  Future<void> archive({
    required Conversation conversation,
    required CommunicationActor actor,
  });

  Future<void> report({
    required Conversation conversation,
    required String reason,
    required CommunicationActor actor,
  });
}
