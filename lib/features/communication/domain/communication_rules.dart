import '../../homework/domain/file_attachment.dart';
import 'conversation.dart';

/// Validation shared by the composer and the repository (the security rules
/// re-check the same limits at commit).
abstract final class CommunicationRules {
  /// Longest message body. Mirrored in `firestore.rules` (`messageBodyOk`).
  static const int maxMessageLength = 2000;
  static const int maxTitleLength = 80;
  static const int maxAttachments = 3;

  static String? validateMessage(
    String body, {
    List<FileAttachment> attachments = const [],
  }) {
    final t = body.trim();
    if (t.isEmpty) return 'Write a message first.';
    if (t.length > maxMessageLength) {
      return 'Keep the message under $maxMessageLength characters '
          '(it is ${t.length}).';
    }
    if (attachments.length > maxAttachments) {
      return 'Attach at most $maxAttachments files.';
    }
    return null;
  }

  static String? validateTitle(String title) {
    final t = title.trim();
    if (t.length < 3) return 'Give the conversation a subject (3+ characters).';
    if (t.length > maxTitleLength) {
      return 'Keep the subject under $maxTitleLength characters.';
    }
    return null;
  }

  /// Whether [userId] may send into [c] right now.
  static String? checkSend(Conversation c, String userId) {
    if (!c.isMember(userId)) return 'You are not part of this conversation.';
    if (c.status != ConversationStatus.open) {
      return c.status == ConversationStatus.closed
          ? 'This conversation is closed. A teacher can reopen it.'
          : 'This conversation is archived.';
    }
    return null;
  }

  static String? checkClose(Conversation c, String userId) {
    if (!c.isMember(userId)) return 'You are not part of this conversation.';
    return c.status == ConversationStatus.open
        ? null
        : 'Only an open conversation can be closed.';
  }

  /// Reopening and archiving are the teacher's (parents cannot reopen).
  static String? checkReopen(Conversation c, String userId) {
    if (userId != c.teacherUserId) {
      return 'Only the teacher can reopen a conversation.';
    }
    return c.status == ConversationStatus.closed
        ? null
        : 'Only a closed conversation can be reopened.';
  }

  static String? checkArchive(Conversation c, String userId) {
    if (userId != c.teacherUserId) {
      return 'Only the teacher can archive a conversation.';
    }
    return c.status == ConversationStatus.closed
        ? null
        : 'Close the conversation before archiving it.';
  }

  static String? checkReport(Conversation c, String userId, String reason) {
    if (!c.isMember(userId)) return 'You are not part of this conversation.';
    if (c.flagged) return 'This conversation has already been reported.';
    if (reason.trim().length < 3) return 'Say briefly what is wrong.';
    return null;
  }

  /// What a notification of a new message may say: who, never what.
  static String previewFor(String senderName) => senderName.trim().isEmpty
      ? 'New message'
      : 'New message from ${senderName.trim()}';
}
