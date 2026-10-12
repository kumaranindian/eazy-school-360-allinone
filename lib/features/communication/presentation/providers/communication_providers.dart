import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../data/firebase_communication_repository.dart';
import '../../domain/communication_repository.dart';
import '../../domain/conversation.dart';

final communicationRepositoryProvider = Provider<CommunicationRepository>(
  (ref) => FirebaseCommunicationRepository(ref.watch(firestoreProvider)),
);

CommunicationActor communicationActorFor(TenantContext t) => CommunicationActor(
  userId: t.user.userId,
  name: t.user.name,
  role: t.role.wireValue,
);

typedef ConversationsKey = ({
  String schoolId,
  String branchId,
  String userId,
  int limit,
});

final branchConversationsProvider = StreamProvider.autoDispose
    .family<List<Conversation>, ConversationsKey>((ref, key) {
      return ref
          .watch(communicationRepositoryProvider)
          .watchMine(
            schoolId: key.schoolId,
            branchId: key.branchId,
            userId: key.userId,
            limit: key.limit,
          );
    }, retry: noRetry);

/// The user's conversations across their branches, most recent first, with
/// the unread total. One bounded listener per branch.
class ConversationList {
  final List<Conversation> items;
  final int unread;
  final bool mayHaveMore;

  const ConversationList(this.items, this.unread, this.mayHaveMore);
}

final conversationListProvider = Provider.autoDispose
    .family<AsyncValue<ConversationList>, int>((ref, limit) {
      final scopeAsync = ref.watch(notificationScopeProvider);
      final scope = scopeAsync.value;
      if (scopeAsync.hasError) {
        return AsyncError(scopeAsync.error!, scopeAsync.stackTrace!);
      }
      if (scope == null) {
        return scopeAsync.isLoading
            ? const AsyncLoading()
            : const AsyncData(ConversationList([], 0, false));
      }
      final all = <Conversation>[];
      var loading = false;
      var more = false;
      for (final b in scope.branchIds) {
        final s = ref.watch(
          branchConversationsProvider((
            schoolId: scope.schoolId,
            branchId: b,
            userId: scope.userId,
            limit: limit,
          )),
        );
        if (s.hasError) return AsyncError(s.error!, s.stackTrace!);
        if (s.isLoading && !s.hasValue) {
          loading = true;
        } else {
          all.addAll(s.value ?? const []);
          if ((s.value?.length ?? 0) >= limit) more = true;
        }
      }
      if (loading) return const AsyncLoading();
      all.sort(
        (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
          a.lastMessageAt ?? DateTime(0),
        ),
      );
      final unread = all.fold<int>(0, (n, c) => n + c.unreadFor(scope.userId));
      return AsyncData(ConversationList(all, unread, more));
    }, retry: noRetry);

typedef ConversationKey = ({
  String schoolId,
  String branchId,
  String conversationId,
});

final conversationProvider = StreamProvider.autoDispose
    .family<Conversation?, ConversationKey>((ref, key) {
      return ref
          .watch(communicationRepositoryProvider)
          .watch(key.schoolId, key.branchId, key.conversationId);
    }, retry: noRetry);

typedef MessagesKey = ({
  String schoolId,
  String branchId,
  String conversationId,
  int limit,
});

final messagesProvider = StreamProvider.autoDispose
    .family<List<Message>, MessagesKey>((ref, key) {
      return ref
          .watch(communicationRepositoryProvider)
          .watchMessages(
            schoolId: key.schoolId,
            branchId: key.branchId,
            conversationId: key.conversationId,
            limit: key.limit,
          );
    }, retry: noRetry);

final conversationEventsProvider = FutureProvider.autoDispose
    .family<List<ConversationEvent>, ConversationKey>((ref, key) {
      return ref
          .watch(communicationRepositoryProvider)
          .fetchEvents(key.schoolId, key.branchId, key.conversationId);
    }, retry: noRetry);

typedef BranchKey2 = ({String schoolId, String branchId});

final reportedConversationsProvider = FutureProvider.autoDispose
    .family<List<Conversation>, BranchKey2>((ref, key) {
      return ref
          .watch(communicationRepositoryProvider)
          .fetchReported(schoolId: key.schoolId, branchId: key.branchId);
    }, retry: noRetry);
