import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_school_admin_repository.dart';
import '../../domain/school_admin.dart';
import 'user_providers.dart';

final schoolAdminRepositoryProvider = Provider<SchoolAdminRepository>(
  (ref) => FirebaseSchoolAdminRepository(ref.watch(firestoreProvider)),
  retry: (retryCount, error) => null,
);

/// The school's administrators, read when the page opens or after one is added.
final schoolAdminsProvider = FutureProvider.autoDispose
    .family<List<SchoolAdminSummary>, String>(
      (ref, schoolId) =>
          ref.watch(schoolAdminRepositoryProvider).list(schoolId),
      retry: (retryCount, error) => null,
    );
