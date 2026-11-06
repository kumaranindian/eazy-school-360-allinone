import 'package:go_router/go_router.dart';

import '../../users/domain/login_provisioning.dart';
import '../../users/presentation/pages/login_access_page.dart';
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
        routes: [
          // Login access as its own full screen (not a dialog on a phone).
          GoRoute(
            path: 'login-access',
            builder: (context, state) => LoginAccessPage(
              kind: LoginKind.parent,
              id: state.pathParameters['parentId']!,
              fallbackName: state.extra is String
                  ? state.extra as String
                  : null,
            ),
          ),
        ],
      ),
    ],
  ),
];
