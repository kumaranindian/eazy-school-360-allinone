import 'package:go_router/go_router.dart';

import 'pages/notification_center_page.dart';
import 'pages/notification_preferences_page.dart';

List<RouteBase> notificationRoutes() => [
  GoRoute(
    path: '/notifications',
    builder: (context, state) => const NotificationCenterPage(),
    routes: [
      GoRoute(
        path: 'preferences',
        builder: (context, state) => const NotificationPreferencesPage(),
      ),
    ],
  ),
];
