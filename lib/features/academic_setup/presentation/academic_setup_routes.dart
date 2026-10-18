import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../school_setup/presentation/pages/branches_page.dart';
import '../../school_setup/presentation/pages/regional_settings_page.dart';
import '../../users/presentation/pages/auth_settings_page.dart';
import 'pages/academic_years_page.dart';
import 'pages/classes_page.dart';
import 'pages/holidays_page.dart';
import 'pages/sections_page.dart';
import 'pages/school_years_page.dart';
import 'pages/settings_overview_page.dart';
import 'pages/subjects_page.dart';
import 'pages/working_days_page.dart';

/// Child routes nested under `/settings` — kept out of `app_router.dart`
/// so that file doesn't grow by one import+line per settings sub-page
/// (the brief: "do not create a huge routing file if the architecture
/// already supports modular route definitions"). `BranchesPage` lives in
/// `school_setup`, not here, but its route is still declared alongside
/// its settings siblings since that's where it appears in navigation.
List<RouteBase> academicSetupRoutes() => [
  GoRoute(
    path: AppRoutes.settings,
    builder: (context, state) => const SettingsOverviewPage(),
    routes: [
      GoRoute(
        path: 'branches',
        builder: (context, state) => const BranchesPage(),
      ),
      GoRoute(
        path: 'academic-years',
        builder: (context, state) => const AcademicYearsPage(),
        routes: [
          GoRoute(
            path: 'school',
            builder: (context, state) => const SchoolYearsPage(),
          ),
        ],
      ),
      GoRoute(
        path: 'classes',
        builder: (context, state) => const ClassesPage(),
      ),
      GoRoute(
        path: 'sections',
        builder: (context, state) => const SectionsPage(),
      ),
      GoRoute(
        path: 'subjects',
        builder: (context, state) => const SubjectsPage(),
      ),
      GoRoute(
        path: 'working-days',
        builder: (context, state) => const WorkingDaysPage(),
      ),
      GoRoute(
        path: 'holidays',
        builder: (context, state) => const HolidaysPage(),
      ),
      GoRoute(
        path: 'regional',
        builder: (context, state) => const RegionalSettingsPage(),
      ),
      GoRoute(
        path: 'authentication',
        builder: (context, state) => const AuthSettingsPage(),
      ),
    ],
  ),
];
