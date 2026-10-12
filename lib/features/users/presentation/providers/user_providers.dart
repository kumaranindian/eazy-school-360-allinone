import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_user_repository.dart';
import '../../domain/user_repository.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
  // The SDK singleton either exists or it does not; retrying cannot help.
  retry: (retryCount, error) => null,
);

/// Shared Firebase Storage instance — used by [SchoolRepository] for the
/// school logo. Kept alongside [firestoreProvider] as the one place both
/// Firebase SDK singletons are exposed to the provider graph.
final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return FirebaseUserRepository(ref.watch(firestoreProvider));
});
