import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import 'pages/help_home_page.dart';
import 'pages/manual_guide_page.dart';

List<RouteBase> helpRoutes() => [
  GoRoute(
    path: AppRoutes.help,
    builder: (context, state) => const HelpHomePage(),
    routes: [
      GoRoute(
        path: 'guides/:guideId',
        builder: (context, state) =>
            ManualGuidePage(guideId: state.pathParameters['guideId']!),
      ),
    ],
  ),
];
