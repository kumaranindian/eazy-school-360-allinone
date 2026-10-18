import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_school_repository.dart';
import '../../domain/branch.dart';
import '../../domain/school_repository.dart';

final schoolRepositoryProvider = Provider<SchoolRepository>((ref) {
  return FirebaseSchoolRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  );
});

final branchesStreamProvider = StreamProvider.autoDispose
    .family<List<Branch>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchBranches(schoolId);
    });
