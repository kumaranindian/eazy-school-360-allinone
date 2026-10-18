import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/firebase_push_gateway.dart';
import '../../domain/push_gateway.dart';
import 'notification_providers.dart';

final pushGatewayProvider = Provider<PushGateway>(
  (ref) => FirebasePushGateway(),
  retry: noRetry,
);

/// Keeps this device's push registration in step with the signed-in user and
/// their preference: registered while push is on, removed when it is off.
/// Watch it from the signed-in shell; it holds no state of its own.
///
/// Best-effort by design — a failed registration must never break the app —
/// and it never prompts when the preference is off.
final pushRegistrationProvider = FutureProvider.autoDispose<void>((ref) async {
  final gateway = ref.watch(pushGatewayProvider);
  if (!gateway.supported) return;
  final scope = await ref.watch(notificationScopeProvider.future);
  if (scope == null) return;
  final prefs = await ref.watch(notificationPreferencesProvider.future);
  final repo = ref.read(notificationRepositoryProvider);
  String? current;

  Future<void> register(String token) async {
    current = token;
    await repo.saveDevice(
      userId: scope.userId,
      token: token,
      platform: gateway.platform,
    );
  }

  try {
    if (!prefs.pushEnabled) {
      final token = await gateway.getToken();
      if (token != null) {
        await repo.removeDevice(userId: scope.userId, token: token);
      }
      return;
    }

    await gateway.initialize();
    var allowed = await gateway.permission() == PushPermission.granted;
    if (!allowed) {
      // A browser ignores a prompt that is not the result of a click, and a
      // refused one cannot be asked again: wait for the user to press
      // "Enable" (see [enablePushOnThisDevice]).
      if (gateway.requiresUserGesture ||
          await gateway.permission() == PushPermission.denied) {
        return;
      }
      allowed = await gateway.requestPermission();
    }
    if (!allowed) return;

    // Never log the token: it is a credential for this device's inbox.
    final token = await gateway.getToken();

    if (token != null) await register(token);
    final sub = gateway.onTokenRefresh.listen((t) {
      final old = current;
      unawaited(() async {
        try {
          if (old != null && old != t) {
            await repo.removeDevice(userId: scope.userId, token: old);
          }
          await register(t);
        } catch (e) {
          AppLogger.error('Push token refresh failed', tag: 'Push', error: e);
        }
      }());
    });
    ref.onDispose(sub.cancel);
  } catch (e) {
    AppLogger.error('Push registration failed', tag: 'Push', error: e);
  }
}, retry: noRetry);

/// Called before sign-out: stops this device receiving the user's
/// notifications. Failures are swallowed so sign-out always proceeds.
///
/// The server removes the registration of the *authenticated caller* from the
/// token alone, so this must work even when the tenant cannot be resolved
/// (the "account inactive" and "create school" pages) — the user id below is
/// informational only.
Future<void> unregisterPushDevice(WidgetRef ref) async {
  try {
    final gateway = ref.read(pushGatewayProvider);
    if (!gateway.supported) return;
    var userId = '';
    try {
      userId =
          (await ref
                  .read(notificationScopeProvider.future)
                  .timeout(const Duration(seconds: 2)))
              ?.userId ??
          '';
    } catch (_) {
      // Tenant not resolvable (inactive account, still loading): go on.
    }
    final token = await gateway.getToken();
    if (token != null) {
      await ref
          .read(notificationRepositoryProvider)
          .removeDevice(userId: userId, token: token);
    }
    await gateway.deleteToken();
  } catch (e) {
    AppLogger.error('Push unregister failed', tag: 'Push', error: e);
  }
}

/// The browser "Enable notifications" button: asks for permission (this must
/// run from a click) and, if granted, registers the device. Returns the
/// resulting permission so the page can explain a refusal.
Future<PushPermission> enablePushOnThisDevice(WidgetRef ref) async {
  final gateway = ref.read(pushGatewayProvider);
  await gateway.requestPermission();
  ref.invalidate(pushRegistrationProvider);
  return gateway.permission();
}

/// This device's current permission, for the settings page.
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>(
  (ref) => ref.watch(pushGatewayProvider).permission(),
  retry: noRetry,
);
