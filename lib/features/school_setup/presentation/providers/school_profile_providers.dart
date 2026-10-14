import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context_provider.dart';
import '../../domain/branch.dart';
import '../../domain/school.dart';
import 'school_providers.dart';

/// Drives the School Profile edit form, the logo upload, and every
/// branch create/edit dialog — one small AsyncNotifier reused across all
/// three, then invalidates [tenantContextProvider] so the rest of the app
/// (which reads the school/branch through `TenantContext`) sees the
/// change immediately instead of showing stale data until next sign-in.
class SchoolProfileWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> updateProfile(School school, {required String updatedBy}) =>
      _run(
        () => ref
            .read(schoolRepositoryProvider)
            .updateSchoolProfile(school, updatedBy: updatedBy),
      );

  Future<bool> uploadLogo({
    required String schoolId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) => _run(() async {
    final url = await ref
        .read(schoolRepositoryProvider)
        .uploadSchoolLogo(
          schoolId: schoolId,
          fileBytes: fileBytes,
          fileExtension: fileExtension,
          updatedBy: updatedBy,
        );
    // The logo lives at a fixed path, so a replacement may be served from
    // the same URL: drop the decoded copy so every shared logo repaints.
    PaintingBinding.instance.imageCache.evict(NetworkImage(url));
  });

  Future<bool> createBranch(Branch branch, {required String createdBy}) => _run(
    () => ref
        .read(schoolRepositoryProvider)
        .createBranch(branch, createdBy: createdBy),
  );

  Future<bool> updateBranch(Branch branch, {required String updatedBy}) => _run(
    () => ref
        .read(schoolRepositoryProvider)
        .updateBranch(branch, updatedBy: updatedBy),
  );

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    if (!state.hasError) {
      ref.invalidate(tenantContextProvider);
    }
    return !state.hasError;
  }
}

final schoolProfileWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<SchoolProfileWriteController, void>(
      SchoolProfileWriteController.new,
    );
