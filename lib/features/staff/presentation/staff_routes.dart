import 'package:go_router/go_router.dart';

import 'pages/my_staff_profile_page.dart';
import 'pages/staff_bulk_import_page.dart';
import 'pages/staff_config_page.dart';
import 'pages/staff_form_page.dart';
import 'pages/staff_list_page.dart';
import 'pages/staff_profile_page.dart';
import 'pages/teachers_list_page.dart';
import 'widgets/staff_config_entry.dart';

/// `/staff` and `/teachers` share one shell branch (one nav destination).
/// Fixed segments (`new`, `import`, `departments`, `designations`) are listed before
/// `:staffId` so they are never swallowed as a staff id.
List<RouteBase> staffRoutes() => [
  GoRoute(
    path: '/staff',
    builder: (context, state) => const StaffListPage(),
    routes: [
      GoRoute(path: 'new', builder: (context, state) => const StaffFormPage()),
      GoRoute(
        path: 'import',
        builder: (context, state) => StaffBulkImportPage(
          teachers: state.uri.queryParameters['teachers'] == '1',
        ),
      ),
      GoRoute(
        path: 'departments',
        builder: (context, state) =>
            const StaffConfigPage(kind: StaffConfigKind.department),
      ),
      GoRoute(
        path: 'designations',
        builder: (context, state) =>
            const StaffConfigPage(kind: StaffConfigKind.designation),
      ),
      GoRoute(
        path: ':staffId',
        builder: (context, state) =>
            StaffProfilePage(staffId: state.pathParameters['staffId']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                StaffFormPage(staffId: state.pathParameters['staffId']),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/teachers',
    builder: (context, state) => const TeachersListPage(),
  ),
];

List<RouteBase> myStaffProfileRoutes() => [
  GoRoute(
    path: '/my-profile',
    builder: (context, state) => const MyStaffProfilePage(),
  ),
];
