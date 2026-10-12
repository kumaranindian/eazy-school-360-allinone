import 'package:flutter/widgets.dart' show ValueKey;
import 'package:go_router/go_router.dart';

import '../domain/leave_enums.dart';
import 'pages/leave_applications_page.dart';
import 'pages/leave_apply_pages.dart';
import 'pages/leave_balances_page.dart';
import 'pages/leave_calendar_page.dart';
import 'pages/leave_detail_pages.dart';
import 'pages/leave_hub_page.dart';
import 'pages/leave_notifications_page.dart';
import 'pages/leave_reports_page.dart';
import 'pages/leave_types_page.dart';
import 'pages/my_leave_page.dart';

/// `/leave/**` share one shell branch (the "Leave" nav entry). Fixed segments
/// are listed before `:applicationId` so they are never read as an id.
List<RouteBase> leaveRoutes() => [
  GoRoute(
    path: '/leave',
    builder: (context, state) => const LeaveHubPage(),
    routes: [
      GoRoute(
        path: 'applications',
        builder: (context, state) {
          final kind = state.uri.queryParameters['kind'];
          final status = state.uri.queryParameters['status'];
          return LeaveApplicationsPage(
            // A new ?kind/?status is a new query, not a stale page.
            key: ValueKey('$kind/$status'),
            initialKind: kind == 'STAFF' ? LeaveKind.staff : LeaveKind.student,
            initialStatus: status == null
                ? null
                : LeaveStatus.values
                      .where((s) => s.wireValue == status)
                      .firstOrNull,
          );
        },
        routes: [
          GoRoute(
            path: ':applicationId',
            builder: (context, state) => LeaveApplicationPage(
              applicationId: state.pathParameters['applicationId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: 'apply',
        builder: (context, state) => const AdminApplyPage(),
      ),
      GoRoute(
        path: 'types',
        builder: (context, state) => const LeaveTypesPage(),
      ),
      GoRoute(
        path: 'balances',
        builder: (context, state) => const LeaveBalancesPage(),
      ),
      GoRoute(
        path: 'calendar',
        builder: (context, state) => const LeaveCalendarPage(),
      ),
      GoRoute(
        path: 'reports',
        builder: (context, state) => const LeaveReportsPage(),
      ),
    ],
  ),
];

/// The self-service area: a staff member's own leave, or a parent's children's.
List<RouteBase> myLeaveRoutes() => [
  GoRoute(
    path: '/my-leave',
    builder: (context, state) => const MyLeavePage(),
    routes: [
      GoRoute(
        path: 'apply',
        builder: (context, state) => MyLeaveApplyPage(
          studentId: state.uri.queryParameters['studentId'],
          branchId: state.uri.queryParameters['b'],
        ),
      ),
      GoRoute(
        path: 'notifications',
        builder: (context, state) => const LeaveNotificationsPage(),
      ),
      GoRoute(
        path: 'applications/:applicationId',
        builder: (context, state) => MyLeaveApplicationPage(
          applicationId: state.pathParameters['applicationId']!,
          branchId: state.uri.queryParameters['b'],
        ),
      ),
    ],
  ),
];
