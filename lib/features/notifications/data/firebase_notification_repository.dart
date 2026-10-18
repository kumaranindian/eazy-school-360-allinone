import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/feed_item.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_repository.dart';
import '../domain/read_ids.dart';

class FirebaseNotificationRepository implements NotificationRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions Function() _functions;

  FirebaseNotificationRepository(
    this._firestore, [
    FirebaseFunctions Function()? functions,
  ]) : _functions = functions ?? appFunctions;

  CollectionReference<Map<String, dynamic>> _notifications(
    String s,
    String b,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(s)
      .collection(FirestoreFields.branchesCollection)
      .doc(b)
      .collection(FirestoreFields.notificationsCollection);

  DocumentReference<Map<String, dynamic>> _readDoc(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('noticeReads')
      .doc('state');

  DocumentReference<Map<String, dynamic>> _prefDoc(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('preferences')
      .doc('notifications');

  FeedItem _item(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String branchId,
    FeedSource source,
  ) {
    final m = d.data();
    return FeedItem(
      id: d.id,
      source: source,
      branchId: branchId,
      type: m['type'] as String? ?? '',
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      createdAt: (m[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      expiresAt: (m['expiresAt'] as Timestamp?)?.toDate(),
      read: m['readAt'] != null,
      refType: m['refType'] as String?,
      refId: m['refId'] as String?,
      applicationId: m['applicationId'] as String?,
      homeworkId: m['homeworkId'] as String?,
      submissionId: m['submissionId'] as String?,
      conversationId: m['conversationId'] as String?,
    );
  }

  Query<Map<String, dynamic>> _mine(String s, String b, String userId) =>
      _notifications(s, b)
          .where('audience', isEqualTo: 'USER')
          .where('recipientUserId', isEqualTo: userId);

  @override
  Stream<List<FeedItem>> watchTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
    required int limit,
  }) => _mine(schoolId, branchId, userId)
      .orderBy(FirestoreFields.createdAt, descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) _item(d, branchId, FeedSource.targeted),
        ],
      );

  @override
  Future<int> countUnreadTargeted({
    required String schoolId,
    required String branchId,
    required String userId,
  }) async {
    try {
      final agg = await _mine(
        schoolId,
        branchId,
        userId,
      ).where('readAt', isNull: true).count().get();
      return agg.count ?? 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> markRead({
    required String schoolId,
    required String branchId,
    required String notificationId,
  }) async {
    try {
      await _notifications(
        schoolId,
        branchId,
      ).doc(notificationId).update({'readAt': FieldValue.serverTimestamp()});
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> markAllRead({
    required String schoolId,
    required String branchId,
    required String userId,
  }) async {
    try {
      var total = 0;
      // Bounded: at most 10 batches of 200 per call; call again for more.
      for (var i = 0; i < 10; i++) {
        final snap = await _mine(
          schoolId,
          branchId,
          userId,
        ).where('readAt', isNull: true).limit(200).get();
        if (snap.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final d in snap.docs) {
          batch.update(d.reference, {'readAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
        total += snap.docs.length;
        if (snap.docs.length < 200) break;
      }
      return total;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<FeedItem>> fetchReviewerNotices({
    required String schoolId,
    required String branchId,
    int limit = 50,
  }) async {
    try {
      final snap = await _notifications(schoolId, branchId)
          .where('audience', isEqualTo: 'REVIEWERS')
          .orderBy(FirestoreFields.createdAt, descending: true)
          .limit(limit)
          .get();
      return [for (final d in snap.docs) _item(d, branchId, FeedSource.shared)];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Set<String>> fetchReadIds(String userId) async {
    try {
      final snap = await _readDoc(userId).get();
      return {
        for (final v in (snap.data()?['ids'] as List? ?? [])) v as String,
      };
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> addReadIds(String userId, Set<String> ids) async {
    if (ids.isEmpty) return;
    try {
      // Read-merge-write inside a transaction: two devices marking different
      // notices read at once must not overwrite each other's ids (STATE-4).
      final ref = _readDoc(userId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final cur = [
          for (final v in (snap.data()?['ids'] as List? ?? [])) v as String,
        ];
        tx.set(ref, {
          'ids': mergeReadIds(cur, ids),
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        });
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<NotificationPreferences> fetchPreferences(String userId) async {
    try {
      final snap = await _prefDoc(userId).get();
      return NotificationPreferences.fromMap(snap.data());
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> savePreferences(
    String userId,
    NotificationPreferences prefs,
  ) async {
    try {
      await _prefDoc(userId).set({
        ...prefs.toMap(),
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  // Devices are registered by the registerDevice Cloud Function, never written
  // from the client: the server records the token under the caller's own
  // school and moves it off any other account that held it.
  @override
  Future<void> saveDevice({
    required String userId,
    required String token,
    required String platform,
  }) async {
    try {
      await _functions().httpsCallable('registerDevice').call({
        'token': token,
        'platform': platform,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> removeDevice({
    required String userId,
    required String token,
  }) async {
    try {
      await _functions().httpsCallable('unregisterDevice').call({
        'token': token,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
