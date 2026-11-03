import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';

import '../logging/app_logger.dart';

/// Forces the Play Store "immediate" update flow whenever a newer version is
/// published: a full-screen update the user cannot dismiss.
///
/// Only runs on Android release builds installed from Google Play (the Play
/// API fails elsewhere, which is ignored). Checked on every app open and each
/// time the app returns to the foreground, so an update that was interrupted
/// is resumed. Failures never block the app.
class ForcedAppUpdate extends StatefulWidget {
  final Widget child;
  const ForcedAppUpdate({super.key, required this.child});

  /// Whether this build can use the Play in-app update API.
  static bool get supported =>
      kReleaseMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  State<ForcedAppUpdate> createState() => _ForcedAppUpdateState();
}

class _ForcedAppUpdateState extends State<ForcedAppUpdate>
    with WidgetsBindingObserver {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!ForcedAppUpdate.supported || _running) return;
    _running = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;
      if (available && info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      // Not installed from Play, offline, or Play unavailable: carry on.
      AppLogger.trace('In-app update check skipped: $e');
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
