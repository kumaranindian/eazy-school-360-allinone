import 'package:go_router/go_router.dart';

import 'pages/period_sets_page.dart';
import 'pages/substitution_pages.dart';
import 'pages/timetable_conflicts_page.dart';
import 'pages/timetable_editor_page.dart';
import 'pages/timetable_hub_page.dart';
import 'pages/timetable_views_pages.dart';

/// `/timetable/**` share one shell branch (the "Timetable" nav entry). Fixed
/// segments are listed before parameterised ones.
List<RouteBase> timetableRoutes() => [
  GoRoute(
    path: '/timetable',
    builder: (context, state) => const TimetableHubPage(),
    routes: [
      GoRoute(
        path: 'periods',
        builder: (context, state) => const PeriodSetsPage(),
      ),
      GoRoute(
        path: 'view',
        builder: (context, state) => const SectionTimetablePage(),
      ),
      GoRoute(
        path: 'teachers',
        builder: (context, state) => const TeacherTimetablePage(),
      ),
      GoRoute(
        path: 'conflicts',
        builder: (context, state) => const TimetableConflictsPage(),
      ),
      GoRoute(
        path: 'history',
        builder: (context, state) => const TimetableHistoryPage(),
      ),
      GoRoute(
        path: 'substitutions',
        builder: (context, state) => const SubstitutionsPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const NewSubstitutionPage(),
          ),
        ],
      ),
      GoRoute(
        path: 'editor/:timetableId',
        builder: (context, state) => TimetableEditorPage(
          timetableId: state.pathParameters['timetableId']!,
        ),
      ),
    ],
  ),
];

/// A teacher's own timetable, or a parent's view of the linked child's class.
List<RouteBase> myTimetableRoutes() => [
  GoRoute(
    path: '/my-timetable',
    builder: (context, state) => const MyTimetablePage(),
  ),
];
