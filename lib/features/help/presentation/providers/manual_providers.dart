import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_manual_progress_repository.dart';
import '../../domain/manual_models.dart';
import '../../domain/manual_progress_repository.dart';

final manualProgressRepositoryProvider = Provider<ManualProgressRepository>(
  (ref) => FirebaseManualProgressRepository(ref.watch(firestoreProvider)),
);

/// The signed-in user's saved place in every guide, keyed by guide id.
/// A failure to read progress must never block reading the manual, so pages
/// treat an error as "no progress yet".
final manualProgressProvider =
    StreamProvider.autoDispose<Map<String, ManualProgress>>((ref) {
      final userId = ref.watch(tenantContextProvider).value?.user.userId;
      if (userId == null) return Stream.value(const {});
      return ref.watch(manualProgressRepositoryProvider).watch(userId);
    }, retry: (retryCount, error) => null);
