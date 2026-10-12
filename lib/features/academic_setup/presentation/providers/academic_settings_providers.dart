import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_academic_settings_repository.dart';
import '../../domain/academic_settings_repository.dart';
import 'academic_setup_keys.dart';

final academicSettingsRepositoryProvider = Provider<AcademicSettingsRepository>(
  (ref) {
    return FirebaseAcademicSettingsRepository(ref.watch(firestoreProvider));
  },
);

final academicSettingsProvider = FutureProvider.autoDispose.family((
  ref,
  BranchKey key,
) {
  return ref
      .watch(academicSettingsRepositoryProvider)
      .getSettings(key.schoolId, key.branchId);
});

class AcademicSettingsWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final academicSettingsWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<AcademicSettingsWriteController, void>(
      AcademicSettingsWriteController.new,
    );
