import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/regional/regional_settings.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import 'school_providers.dart';

/// Drives the "create your school" form's submit button, then refreshes
/// [tenantContextProvider] so the router picks up the new profile and
/// moves on to `/dashboard`.
class CreateSchoolController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> createSchool({
    required String schoolName,
    required String schoolEmail,
    String? schoolPhone,
    required RegionalSettings regional,
  }) async {
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (currentUser == null) {
      state = AsyncError(const AuthFailure(), StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(schoolRepositoryProvider)
          .createSchoolForCurrentUser(
            userId: currentUser.uid,
            userName:
                currentUser.displayName ?? currentUser.email ?? 'School Admin',
            userEmail: currentUser.email ?? '',
            schoolName: schoolName,
            schoolEmail: schoolEmail,
            schoolPhone: schoolPhone,
            regional: regional,
          );
      ref.invalidate(tenantContextProvider);
    });

    // Log the state after operation
    if (state.hasError) {
      AppLogger.error(
        'School creation controller error: ${state.error}',
        tag: 'SchoolCreation',
      );
    }
  }
}

final createSchoolControllerProvider =
    AsyncNotifierProvider<CreateSchoolController, void>(
      CreateSchoolController.new,
    );
