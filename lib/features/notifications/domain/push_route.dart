import '../../../core/routing/app_routes.dart';

/// Where tapping a push may take the user. A push payload is data from the
/// network, so it never names an arbitrary destination: only the routes below
/// are honoured, anything else (or nothing) opens the notification centre,
/// which lists the item and applies the role-aware [NotificationNavigator]
/// and the router's own permission checks.
abstract final class PushRoute {
  static const _allowed = {AppRoutes.notifications};

  static String resolve(Map<String, String>? data) {
    final requested = data?['route'];
    if (requested != null && _allowed.contains(requested)) return requested;
    return AppRoutes.notifications;
  }
}
