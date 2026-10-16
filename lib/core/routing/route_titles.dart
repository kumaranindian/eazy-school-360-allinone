import 'app_routes.dart';

/// The centre text of the branding header for the screen at a location: the
/// module's own name, so the header answers "where am I" while the school
/// logo answers "whose school". Null means "no module title" — the header
/// then shows the school name (the dashboard).
///
/// Matching is by the longest route prefix, so every nested screen
/// (`/fees/invoices/123`, `/students/new`, …) inherits its module's title
/// without being listed one by one. Pure: unit-tested without a router.
String? screenTitleForPath(String path) {
  final p = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  String? best;
  var bestLen = -1;
  for (final e in _titles.entries) {
    final prefix = e.key;
    final matches = p == prefix || p.startsWith('$prefix/');
    if (matches && prefix.length > bestLen) {
      best = e.value;
      bestLen = prefix.length;
    }
  }
  return best;
}

const Map<String, String> _titles = {
  AppRoutes.school: 'School Profile',
  AppRoutes.settings: 'School Settings',
  AppRoutes.students: 'Students',
  AppRoutes.parents: 'Parents',
  AppRoutes.staff: 'Staff and Teachers',
  AppRoutes.teachers: 'Teachers',
  AppRoutes.attendance: 'Attendance',
  AppRoutes.attendanceReports: 'Attendance Reports',
  AppRoutes.fees: 'Fees Management',
  AppRoutes.feeReports: 'Fee Reports',
  AppRoutes.myFees: 'My Fees',
  AppRoutes.leave: 'Leave Management',
  AppRoutes.leaveReports: 'Leave Reports',
  AppRoutes.myLeave: 'My Leave',
  AppRoutes.timetable: 'Timetable',
  AppRoutes.myTimetable: 'My Timetable',
  AppRoutes.homework: 'Homework',
  AppRoutes.myHomework: 'My Homework',
  AppRoutes.announcements: 'Announcements',
  AppRoutes.exams: 'Exams',
  AppRoutes.myAttendance: 'My Attendance',
  AppRoutes.myResults: 'My Results',
  AppRoutes.notifications: 'Notifications',
  AppRoutes.messages: 'Messages',
  AppRoutes.myProfile: 'My Profile',
  AppRoutes.users: 'User Management',
};
