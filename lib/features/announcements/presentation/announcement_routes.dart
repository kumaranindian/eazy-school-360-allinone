import 'package:go_router/go_router.dart';

import 'pages/announcement_detail_page.dart';
import 'pages/announcement_form_page.dart';
import 'pages/announcements_page.dart';

/// `/announcements/**` share one shell branch. Fixed segments come before
/// parameterised ones.
List<RouteBase> announcementRoutes() => [
  GoRoute(
    path: '/announcements',
    builder: (context, state) => const AnnouncementsPage(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const AnnouncementFormPage(),
      ),
      GoRoute(
        path: 'edit/:announcementId',
        builder: (context, state) => AnnouncementFormPage(
          announcementId: state.pathParameters['announcementId']!,
          branchId: state.uri.queryParameters['branchId'],
        ),
      ),
      GoRoute(
        path: 'detail/:announcementId',
        builder: (context, state) => AnnouncementDetailPage(
          announcementId: state.pathParameters['announcementId']!,
          branchId: state.uri.queryParameters['branchId'],
        ),
      ),
    ],
  ),
];
