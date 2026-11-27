import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// For list pages that fetch once (STU-01-DEF-02, HW-01-DEF-01,
/// COM-01-DEF-01). Their create, edit and detail pages are child routes
/// (`/students/new`, `/homework/:id`, ...), and the shell keeps the list
/// mounted underneath, so without this the list shows the data of its first
/// load. [onReturn] runs each time the page's own route is current again
/// after another route was on top, so a create, edit or delete made there
/// shows at once.
mixin ReloadOnReturn<T extends StatefulWidget> on State<T> {
  GoRouter? _router;
  String? _ownPath;
  bool _away = false;

  /// Reload the list (and anything counted from it).
  void onReturn();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router == _router) return;
    _router?.routeInformationProvider.removeListener(_routeChanged);
    _router = router;
    if (router == null) return;
    try {
      _ownPath ??= GoRouterState.of(context).uri.path;
    } catch (_) {
      return; // not inside a GoRoute page (e.g. a test harness)
    }
    router.routeInformationProvider.addListener(_routeChanged);
  }

  void _routeChanged() {
    final router = _router;
    if (router == null || !mounted) return;
    final path = router.routeInformationProvider.value.uri.path;
    if (path != _ownPath) {
      _away = true;
    } else if (_away) {
      _away = false;
      onReturn();
    }
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_routeChanged);
    super.dispose();
  }
}
