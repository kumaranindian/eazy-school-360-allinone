import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../announcements/presentation/providers/announcement_providers.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../homework/presentation/providers/homework_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_notification_repository.dart';
import '../../domain/feed_item.dart';
import '../../domain/notification_preferences.dart';
import '../../domain/notification_repository.dart';

/// Failed notification/message loads are shown (with a retry button) rather
/// than silently retried in the background: the bell sits in every screen's
/// app bar and must never keep timers or listeners alive after an error.
Duration? noRetry(int retryCount, Object error) => null;

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => FirebaseNotificationRepository(ref.watch(firestoreProvider)),
  retry: noRetry,
);

/// Who the centre is for: the user and the branches their notifications live
/// in (a parent's children may attend several).
class NotificationScope {
  final String schoolId;
  final String userId;
  final UserRole role;
  final String? parentId;
  final List<String> branchIds;
  final bool canReviewLeave;

  const NotificationScope({
    required this.schoolId,
    required this.userId,
    required this.role,
    required this.parentId,
    required this.branchIds,
    required this.canReviewLeave,
  });

  String get branchKey => branchIds.join(',');
}

final notificationScopeProvider =
    FutureProvider.autoDispose<NotificationScope?>((ref) async {
      final tenant = await ref.watch(tenantContextProvider.future);
      final schoolId = tenant?.school?.schoolId;
      if (tenant == null || schoolId == null) return null;
      final branches = <String>{};
      final own = tenant.user.branchId ?? tenant.branch?.branchId;
      if (own != null) branches.add(own);
      final parentId = tenant.user.linkedParentId;
      if (tenant.role == UserRole.parent && parentId != null) {
        try {
          final kids = await ref.watch(
            linkedChildrenProvider((
              schoolId: schoolId,
              parentId: parentId,
            )).future,
          );
          branches.addAll(kids.map((c) => c.branchId));
        } catch (_) {
          // Fall back to the user's own branch.
        }
      }
      return NotificationScope(
        schoolId: schoolId,
        userId: tenant.user.userId,
        role: tenant.role,
        parentId: parentId,
        branchIds: branches.toList()..sort(),
        canReviewLeave: tenant.can(Permission.reviewLeave),
      );
    }, retry: noRetry);

typedef TargetedKey = ({
  String schoolId,
  String branchId,
  String userId,
  int limit,
});

/// One branch's own notifications — a live listener bounded by `limit`,
/// released when nothing watches it.
final targetedFeedProvider = StreamProvider.autoDispose
    .family<List<FeedItem>, TargetedKey>((ref, key) {
      return ref
          .watch(notificationRepositoryProvider)
          .watchTargeted(
            schoolId: key.schoolId,
            branchId: key.branchId,
            userId: key.userId,
            limit: key.limit,
          );
    }, retry: noRetry);

final readIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final scope = await ref.watch(notificationScopeProvider.future);
  if (scope == null) return const {};
  return ref.watch(notificationRepositoryProvider).fetchReadIds(scope.userId);
}, retry: noRetry);

final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) async {
      final scope = await ref.watch(notificationScopeProvider.future);
      if (scope == null) return const NotificationPreferences();
      return ref
          .watch(notificationRepositoryProvider)
          .fetchPreferences(scope.userId);
    }, retry: noRetry);

/// Audience notices (announcements, homework, results) the user is addressed
/// by, and reviewers' notices when they may review leave.
final sharedFeedProvider = FutureProvider.autoDispose<List<FeedItem>>((
  ref,
) async {
  final scope = await ref.watch(notificationScopeProvider.future);
  if (scope == null || scope.branchIds.isEmpty) return const [];
  final role = scope.role.wireValue;
  final viewer = await ref.watch(
    announcementViewerProvider((
      schoolId: scope.schoolId,
      branchId: scope.branchIds.first,
      userId: scope.userId,
      role: role,
      parentId: scope.parentId,
    )).future,
  );
  final items = <FeedItem>[];
  final notices = await ref.watch(
    visibleNoticesProvider((
      schoolId: scope.schoolId,
      branchIds: scope.branchKey,
      role: role,
      parentId: scope.parentId,
    )).future,
  );
  for (final n in notices) {
    if (!noticeAddressedTo(n, viewer)) continue;
    items.add(
      FeedItem(
        id: n.noticeId,
        source: FeedSource.shared,
        branchId: n.branchId,
        type: n.type,
        title: n.title,
        body: n.body ?? '',
        createdAt: n.createdAt,
        refType: n.refType,
        refId: n.refId,
      ),
    );
  }
  if (scope.canReviewLeave) {
    final repo = ref.watch(notificationRepositoryProvider);
    for (final b in scope.branchIds) {
      try {
        items.addAll(
          await repo.fetchReviewerNotices(
            schoolId: scope.schoolId,
            branchId: b,
          ),
        );
      } catch (_) {
        // A branch the user may not review simply contributes nothing.
      }
    }
  }
  return items;
}, retry: noRetry);

/// The merged, preference-filtered, newest-first feed.
class FeedState {
  final List<FeedItem> items;
  final int unread;

  /// Whether a targeted listener hit its limit (more may exist).
  final bool mayHaveMore;

  const FeedState({
    required this.items,
    required this.unread,
    required this.mayHaveMore,
  });
}

final feedProvider = Provider.autoDispose.family<AsyncValue<FeedState>, int>((
  ref,
  limit,
) {
  final scopeAsync = ref.watch(notificationScopeProvider);
  final scope = scopeAsync.value;
  if (scopeAsync.hasError) {
    return AsyncError(scopeAsync.error!, scopeAsync.stackTrace!);
  }
  if (scope == null) {
    return scopeAsync.isLoading
        ? const AsyncLoading()
        : const AsyncData(FeedState(items: [], unread: 0, mayHaveMore: false));
  }
  final items = <FeedItem>[];
  var loading = false;
  var more = false;
  for (final b in scope.branchIds) {
    final t = ref.watch(
      targetedFeedProvider((
        schoolId: scope.schoolId,
        branchId: b,
        userId: scope.userId,
        limit: limit,
      )),
    );
    if (t.hasError) return AsyncError(t.error!, t.stackTrace!);
    if (t.isLoading && !t.hasValue) {
      loading = true;
    } else {
      items.addAll(t.value ?? const []);
      if ((t.value?.length ?? 0) >= limit) more = true;
    }
  }
  final shared = ref.watch(sharedFeedProvider);
  final reads = ref.watch(readIdsProvider);
  final prefs = ref.watch(notificationPreferencesProvider);
  if (shared.hasError) return AsyncError(shared.error!, shared.stackTrace!);
  // A refresh (a new notice arriving) keeps the previous value, so the count
  // does not drop to zero while it recomputes.
  bool pending(AsyncValue v) => v.isLoading && !v.hasValue;
  if (loading || pending(shared) || pending(reads) || pending(prefs)) {
    return const AsyncLoading();
  }
  final readIds = reads.value ?? const <String>{};
  final p = prefs.value ?? const NotificationPreferences();
  final now = DateTime.now();
  for (final s in shared.value ?? const <FeedItem>[]) {
    items.add(s.copyWith(read: readIds.contains(s.id)));
  }
  final visible =
      [
        for (final i in items)
          if (!i.isExpired(now) && p.shows(i.category)) i,
      ]..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
  return AsyncData(
    FeedState(
      items: visible,
      unread: visible.where((i) => !i.read).length,
      mayHaveMore: more,
    ),
  );
}, retry: noRetry);

/// The unread count for the bell — the same number the centre shows: the
/// user's own notifications (newest 30 per branch) plus audience notices
/// (announcements, homework, results; newest 30 per branch, live), minus
/// muted categories and anything already read. Capped to "9+" by the bell.
final unreadBadgeProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(feedProvider(30)).value?.unread ?? 0,
  retry: noRetry,
);

/// Marks one item read: its own `readAt`, or the user's read list.
Future<void> markFeedItemRead(WidgetRef ref, FeedItem item) async {
  if (item.read) return;
  final scope = await ref.read(notificationScopeProvider.future);
  if (scope == null) return;
  final repo = ref.read(notificationRepositoryProvider);
  if (item.source == FeedSource.targeted) {
    await repo.markRead(
      schoolId: scope.schoolId,
      branchId: item.branchId,
      notificationId: item.id,
    );
  } else {
    await repo.addReadIds(scope.userId, {item.id});
    ref.invalidate(readIdsProvider);
  }
}

/// Marks everything the user may see as read — their own notifications and
/// their read list; never another user's.
Future<int> markAllFeedRead(WidgetRef ref, List<FeedItem> items) async {
  final scope = await ref.read(notificationScopeProvider.future);
  if (scope == null) return 0;
  final repo = ref.read(notificationRepositoryProvider);
  var n = 0;
  for (final b in scope.branchIds) {
    n += await repo.markAllRead(
      schoolId: scope.schoolId,
      branchId: b,
      userId: scope.userId,
    );
  }
  final shared = {
    for (final i in items)
      if (i.source == FeedSource.shared && !i.read) i.id,
  };
  await repo.addReadIds(scope.userId, shared);
  ref.invalidate(readIdsProvider);
  return n + shared.length;
}

/// The announcement repository is only used here for notices; exposed so
/// tests can override one place.
final noticeSourceProvider = announcementRepositoryProvider;
