import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_parent_repository.dart';
import '../../domain/parent.dart';
import '../../domain/parent_repository.dart';
import '../../domain/student.dart';
import 'student_keys.dart';

final parentRepositoryProvider = Provider<ParentRepository>((ref) {
  return FirebaseParentRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  );
});

final parentProvider = StreamProvider.autoDispose.family<Parent?, ParentKey>((
  ref,
  key,
) {
  return ref
      .watch(parentRepositoryProvider)
      .watchParent(key.schoolId, key.branchId, key.parentId);
});

/// One-shot (not a stream — a collection-group query, not a single
/// document/collection to listen on) — the Parent profile page re-reads
/// this after any link change instead of keeping a live listener open.
final childrenForParentProvider = FutureProvider.autoDispose
    .family<
      List<Student>,
      ({String schoolId, String parentId, String? branchId})
    >((ref, key) {
      return ref
          .read(parentRepositoryProvider)
          .getChildrenForParent(
            schoolId: key.schoolId,
            parentId: key.parentId,
            branchId: key.branchId,
          );
    });

class ParentWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> createParent(
    Parent parent, {
    required String createdBy,
  }) async {
    String? newId;
    final ok = await _run(() async {
      newId = await ref
          .read(parentRepositoryProvider)
          .createParent(parent, createdBy: createdBy);
    });
    return ok ? newId : null;
  }

  Future<bool> updateParent(Parent parent, {required String updatedBy}) => _run(
    () => ref
        .read(parentRepositoryProvider)
        .updateParent(parent, updatedBy: updatedBy),
  );

  Future<bool> uploadPhoto({
    required String schoolId,
    required String branchId,
    required String parentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(parentRepositoryProvider)
        .uploadParentPhoto(
          schoolId: schoolId,
          branchId: branchId,
          parentId: parentId,
          fileBytes: fileBytes,
          fileExtension: fileExtension,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> linkPortalAccess({
    required String schoolId,
    required String branchId,
    required String parentId,
    required String userId,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(parentRepositoryProvider)
        .linkPortalAccess(
          schoolId: schoolId,
          branchId: branchId,
          parentId: parentId,
          userId: userId,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final parentWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<ParentWriteController, void>(
      ParentWriteController.new,
    );
