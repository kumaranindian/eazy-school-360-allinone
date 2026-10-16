import 'package:go_router/go_router.dart';

import 'pages/attendance_hub_page.dart';
import 'pages/attendance_reports_page.dart';
import 'pages/my_attendance_page.dart';
import 'pages/staff_attendance_page.dart';
import 'pages/student_attendance_page.dart';

/// `/attendance` and its children share one shell branch (one nav entry).
List<RouteBase> attendanceRoutes() => [
  GoRoute(
    path: '/attendance',
    builder: (context, state) => const AttendanceHubPage(),
    routes: [
      GoRoute(
        path: 'students',
        builder: (context, state) => const StudentAttendancePage(),
      ),
      GoRoute(
        path: 'staff',
        builder: (context, state) => const StaffAttendancePage(),
      ),
      GoRoute(
        path: 'reports',
        builder: (context, state) => const AttendanceReportsPage(),
      ),
    ],
  ),
];

/// A parent's read-only view of the linked children's attendance.
List<RouteBase> myAttendanceRoutes() => [
  GoRoute(
    path: '/my-attendance',
    builder: (context, state) => const MyAttendancePage(),
  ),
];
