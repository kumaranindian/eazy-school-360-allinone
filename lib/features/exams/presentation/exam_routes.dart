import 'package:go_router/go_router.dart';

import 'pages/exam_detail_page.dart';
import 'pages/exam_form_page.dart';
import 'pages/exam_history_page.dart';
import 'pages/exam_list_page.dart';
import 'pages/exam_results_page.dart';
import 'pages/grading_schemes_page.dart';
import 'pages/marks_entry_page.dart';
import 'pages/marks_review_page.dart';
import 'pages/my_results_pages.dart';
import 'pages/performance_page.dart';
import 'pages/student_result_page.dart';

/// `/exams/**` share one shell branch. Fixed segments precede parameterised
/// ones.
List<RouteBase> examRoutes() => [
  GoRoute(
    path: '/exams',
    builder: (context, state) => const ExamListPage(),
    routes: [
      GoRoute(path: 'new', builder: (context, state) => const ExamFormPage()),
      GoRoute(
        path: 'schemes',
        builder: (context, state) => const GradingSchemesPage(),
      ),
      GoRoute(
        path: 'performance',
        builder: (context, state) => const PerformancePage(),
      ),
      GoRoute(
        path: 'edit/:examId',
        builder: (context, state) =>
            ExamFormPage(examId: state.pathParameters['examId']),
      ),
      GoRoute(
        path: 'detail/:examId',
        builder: (context, state) =>
            ExamDetailPage(examId: state.pathParameters['examId']!),
      ),
      GoRoute(
        path: 'marks/:examId/:subjectId/:sectionId',
        builder: (context, state) => MarksEntryPage(
          examId: state.pathParameters['examId']!,
          subjectId: state.pathParameters['subjectId']!,
          sectionId: state.pathParameters['sectionId']!,
        ),
      ),
      GoRoute(
        path: 'review/:examId',
        builder: (context, state) =>
            MarksReviewPage(examId: state.pathParameters['examId']!),
      ),
      GoRoute(
        path: 'history/:examId',
        builder: (context, state) =>
            ExamHistoryPage(examId: state.pathParameters['examId']!),
      ),
      GoRoute(
        path: 'results/:examId',
        builder: (context, state) =>
            ExamResultsPage(examId: state.pathParameters['examId']!),
        routes: [
          GoRoute(
            path: ':studentId',
            builder: (context, state) => StudentResultPage(
              examId: state.pathParameters['examId']!,
              studentId: state.pathParameters['studentId']!,
            ),
          ),
        ],
      ),
    ],
  ),
];

/// A parent's view of the linked children's published results.
List<RouteBase> myResultsRoutes() => [
  GoRoute(
    path: '/my-results',
    builder: (context, state) => const MyResultsPage(),
    routes: [
      GoRoute(
        path: ':examId/:studentId',
        builder: (context, state) => MyResultPage(
          examId: state.pathParameters['examId']!,
          studentId: state.pathParameters['studentId']!,
        ),
      ),
    ],
  ),
];
