import 'package:go_router/go_router.dart';

import 'pages/homework_detail_page.dart';
import 'pages/homework_form_page.dart';
import 'pages/homework_list_page.dart';
import 'pages/homework_review_page.dart';
import 'pages/my_homework_detail_page.dart';
import 'pages/my_homework_page.dart';
import 'pages/submission_review_page.dart';

/// `/homework/**` share one shell branch (the "Homework" nav entry). Fixed
/// segments are listed before parameterised ones.
List<RouteBase> homeworkRoutes() => [
  GoRoute(
    path: '/homework',
    builder: (context, state) => const HomeworkListPage(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const HomeworkFormPage(),
      ),
      GoRoute(
        path: 'edit/:homeworkId',
        builder: (context, state) =>
            HomeworkFormPage(homeworkId: state.pathParameters['homeworkId']!),
      ),
      GoRoute(
        path: 'detail/:homeworkId',
        builder: (context, state) =>
            HomeworkDetailPage(homeworkId: state.pathParameters['homeworkId']!),
      ),
      GoRoute(
        path: 'review/:homeworkId',
        builder: (context, state) =>
            HomeworkReviewPage(homeworkId: state.pathParameters['homeworkId']!),
        routes: [
          GoRoute(
            path: ':studentId',
            builder: (context, state) => SubmissionReviewPage(
              homeworkId: state.pathParameters['homeworkId']!,
              studentId: state.pathParameters['studentId']!,
            ),
          ),
        ],
      ),
    ],
  ),
];

/// A parent's view of the linked children's homework.
List<RouteBase> myHomeworkRoutes() => [
  GoRoute(
    path: '/my-homework',
    builder: (context, state) => const MyHomeworkPage(),
    routes: [
      GoRoute(
        path: ':homeworkId/:studentId',
        builder: (context, state) => MyHomeworkDetailPage(
          homeworkId: state.pathParameters['homeworkId']!,
          studentId: state.pathParameters['studentId']!,
        ),
      ),
    ],
  ),
];
