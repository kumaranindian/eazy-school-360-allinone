import 'package:go_router/go_router.dart';

import 'pages/student_admission_page.dart';
import 'pages/student_bulk_import_page.dart';
import 'pages/student_profile_page.dart';
import 'pages/students_list_page.dart';

/// `/students` and its children — kept out of `app_router.dart`, same
/// pattern as `academic_setup_routes.dart`. `new` and `import` are listed
/// before `:studentId` so they are never swallowed as a student id.
List<RouteBase> studentsRoutes() => [
  GoRoute(
    path: '/students',
    builder: (context, state) => const StudentsListPage(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const StudentAdmissionPage(),
      ),
      GoRoute(
        path: 'import',
        builder: (context, state) => const StudentBulkImportPage(),
      ),
      GoRoute(
        path: ':studentId',
        builder: (context, state) =>
            StudentProfilePage(studentId: state.pathParameters['studentId']!),
      ),
    ],
  ),
];
