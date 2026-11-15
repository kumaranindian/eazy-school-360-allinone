import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/firebase_platform_admin_repository.dart';
import '../../domain/platform_admin_entry.dart';
import '../../domain/platform_admin_repository.dart';
import '../../domain/platform_role.dart';

final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>(
  (ref) => FirebasePlatformAdminRepository(),
  retry: (retryCount, error) => null,
);

/// Every platform administrator (owner-only on the server).
final platformAdminsProvider =
    FutureProvider.autoDispose<List<PlatformAdminEntry>>(
      (ref) => ref.watch(platformAdminRepositoryProvider).list(),
      retry: (retryCount, error) => null,
    );

/// What happened when an owner added someone.
enum PlatformAdminCreated {
  /// Account created and the password-setup email sent.
  emailSent,

  /// Account created, but the email could not be sent: use "Send setup email".
  emailFailed,
}

/// Drives the platform-admin actions (add, role, enable/disable, setup email).
class PlatformAdminActions extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? result;
    state = await AsyncValue.guard(() async => result = await action());
    if (state.hasError) return null;
    // Only a change needs the list reloaded; a refusal leaves it as it was.
    ref.invalidate(platformAdminsProvider);
    return result;
  }

  Future<PlatformAdminCreated?> create({
    required String name,
    required String email,
    required PlatformRole role,
  }) => _run(() async {
    final used = await ref
        .read(platformAdminRepositoryProvider)
        .create(name: name, email: email, role: role);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(used);
      return PlatformAdminCreated.emailSent;
    } catch (_) {
      return PlatformAdminCreated.emailFailed;
    }
  });

  Future<bool> setRole(String uid, PlatformRole role) async =>
      await _run(() async {
        await ref
            .read(platformAdminRepositoryProvider)
            .setRole(uid: uid, role: role);
        return true;
      }) ??
      false;

  Future<bool> setActive(String uid, bool active) async =>
      await _run(() async {
        await ref
            .read(platformAdminRepositoryProvider)
            .setActive(uid: uid, active: active);
        return true;
      }) ??
      false;

  Future<bool> sendSetupEmail(String email) async =>
      await _run(() async {
        await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
        return true;
      }) ??
      false;
}

final platformAdminActionsProvider =
    AsyncNotifierProvider.autoDispose<PlatformAdminActions, void>(
      PlatformAdminActions.new,
    );
