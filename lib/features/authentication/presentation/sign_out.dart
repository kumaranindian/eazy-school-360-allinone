import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../notifications/presentation/providers/push_providers.dart';
import 'providers/auth_providers.dart';

bool _signingOut = false;

/// The one way the UI signs a user out.
///
/// 1. Stops this device receiving the user's push notifications — on a shared
///    phone the next person to sign in must not get the previous user's
///    notices (NOTIF-1). Every sign-out button goes through here, including
///    the "account inactive" and "create school" pages.
/// 2. Never waits long for that: a slow or offline network must not keep the
///    previous user signed in (STATE-3), so the cleanup gets
///    [cleanupTimeout]; the server also drops devices that stop checking in
///    and those of disabled accounts.
/// 3. Signs out. A second tap while one is running does nothing.
Future<void> signOutWithCleanup(
  WidgetRef ref, {
  Duration cleanupTimeout = const Duration(seconds: 4),
}) async {
  if (_signingOut) return;
  _signingOut = true;
  try {
    try {
      await unregisterPushDevice(ref).timeout(cleanupTimeout);
    } on TimeoutException {
      AppLogger.warning(
        'Push cleanup timed out; signing out anyway',
        tag: 'SignOut',
      );
    } catch (_) {
      // unregisterPushDevice logs its own failures.
    }
    await ref.read(authRepositoryProvider).signOut();
  } finally {
    _signingOut = false;
  }
}
