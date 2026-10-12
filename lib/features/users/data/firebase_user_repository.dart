import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/user_profile.dart';
import '../domain/user_repository.dart';

class FirebaseUserRepository implements UserRepository {
  final FirebaseFirestore _firestore;

  FirebaseUserRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _doc(String userId) =>
      _firestore.collection(FirestoreFields.usersCollection).doc(userId);

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    AppLogger.debug(
      'getUserProfile: reading ${FirestoreFields.usersCollection}/$userId '
      '(project=${_firestore.app.options.projectId})',
      tag: 'Users',
    );
    try {
      final snapshot = await _doc(userId).get();
      AppLogger.debug(
        'getUserProfile: exists=${snapshot.exists} '
        'fromCache=${snapshot.metadata.isFromCache}',
        tag: 'Users',
      );
      if (!snapshot.exists) return null;
      return UserProfile.fromFirestore(userId, snapshot.data()!);
    } catch (error, stackTrace) {
      AppLogger.error(
        'getUserProfile failed for uid=$userId',
        tag: 'Users',
        error: error,
        stackTrace: stackTrace,
      );
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<UserProfile?> watchUserProfile(String userId) {
    return _doc(userId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return UserProfile.fromFirestore(userId, snapshot.data()!);
        })
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<void> updateOwnProfile(UserProfile profile) async {
    try {
      await _doc(
        profile.userId,
      ).update(profile.toFirestoreSelfUpdate(updatedBy: profile.userId));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
