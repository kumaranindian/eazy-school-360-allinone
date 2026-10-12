import 'package:go_router/go_router.dart';

import 'pages/parent_profile_page.dart';
import 'pages/parents_list_page.dart';

List<RouteBase> parentsRoutes() => [
  GoRoute(
    path: '/parents',
    builder: (context, state) => const ParentsListPage(),
    routes: [
      GoRoute(
        path: ':parentId',
        builder: (context, state) =>
            ParentProfilePage(parentId: state.pathParameters['parentId']!),
      ),
    ],
  ),
];
