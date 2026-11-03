import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

/// Where the system back gesture/button should go from [path], or null when
/// [path] is the home screen (the app would close, so we ask first).
///
/// Pure, so it is unit-tested without a router:
/// - the dashboard (`/dashboard`) -> null (confirm before closing);
/// - the More page -> the dashboard;
/// - a module's own screens (`/fees/structures`, `/my-leave/apply`, ...) ->
///   that module's main screen (`/fees`, `/my-leave`);
/// - a module's main screen (`/fees`) -> the dashboard.
String? backTargetFor(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return AppRoutes.dashboard;
  if (segments.first == 'dashboard') {
    return segments.length > 1 ? AppRoutes.dashboard : null;
  }
  return segments.length > 1 ? '/${segments.first}' : AppRoutes.dashboard;
}

/// Android's back gesture / button. Without this, going back from a screen
/// that was opened with `go` (a bottom-bar tab, a hub tile) closes the app
/// straight away. With it:
///
/// - inside a module, back goes up one level, then to the dashboard;
/// - on the dashboard, back asks "Close the app?" and only then exits.
///
/// Screens that were pushed on top still pop normally first (the router
/// handles those before this guard sees the event). Does nothing on the web
/// and on iOS, where the platform behaves as before.
class BackExitGuard extends StatelessWidget {
  final Widget child;
  final String path;

  /// Overridable for tests; defaults to "Android app, not web".
  final bool? enabled;

  const BackExitGuard({
    super.key,
    required this.child,
    required this.path,
    this.enabled,
  });

  static bool get _isAndroidApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _confirmExit(BuildContext context) async {
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close the app?'),
        content: const Text('Do you want to exit EazySchool 360?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close app'),
          ),
        ],
      ),
    );
    return close ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? _isAndroidApp)) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final target = backTargetFor(path);
        if (target != null) {
          context.go(target);
          return;
        }
        if (await _confirmExit(context)) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
