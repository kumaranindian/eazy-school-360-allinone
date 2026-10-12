import 'user_profile.dart';

/// Boundary between the rest of the app and wherever user profiles are
/// actually stored (Firestore today). Throws an `AppFailure` (via
/// error_mapper) on failure.
abstract class UserRepository {
  /// Null means "signed in, but no profile exists yet" — the caller is a
  /// brand-new account that hasn't created or joined a school.
  Future<UserProfile?> getUserProfile(String userId);

  Stream<UserProfile?> watchUserProfile(String userId);

  Future<void> updateOwnProfile(UserProfile profile);
}
