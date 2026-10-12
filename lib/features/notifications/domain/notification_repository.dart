import 'feed_item.dart';
import 'notification_preferences.dart';

abstract class NotificationRepository {
  /// This user's own notifications of one branch, newest first, up to
  /// [limit]. A live listener, bounded by the limit.
  Stream<List<FeedItem>> watchTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  });

  /// Unread targeted notifications (aggregate query: no documents are
  /// downloaded, so this stays correct however many exist).
  Future<int> countUnreadTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
  });

  Future<void> markRead({
    required String schoolId,
    required String branchId,
    required String notificationId,
  });

  /// Marks the user's unread targeted notifications of the branch read, in
  /// batches. Returns how many.
  Future<int> markAllRead({
    required String schoolId,
    required String branchId,
    required String userId,
  });

  /// Reviewers' notices (for users who may review leave).
  Future<List<FeedItem>> fetchReviewerNotices({
    required String schoolId,
    required String branchId,
    int limit = 50,
  });

  Future<Set<String>> fetchReadIds(String userId);

  /// Adds [ids] to the user's read list (newest 500 kept).
  Future<void> addReadIds(String userId, Set<String> ids);

  Future<NotificationPreferences> fetchPreferences(String userId);

  Future<void> savePreferences(String userId, NotificationPreferences prefs);

  /// Records this device's push token under the user. The document id is
  /// derived from the token, so registering twice is idempotent.
  Future<void> saveDevice({
    required String userId,
    required String token,
    required String platform,
  });

  /// Forgets this device's token (turning push off, or signing out).
  Future<void> removeDevice({required String userId, required String token});
}
