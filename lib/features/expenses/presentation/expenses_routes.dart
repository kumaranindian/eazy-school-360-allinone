import 'package:go_router/go_router.dart';

import 'pages/expense_detail_page.dart';
import 'pages/expense_form_page.dart';
import 'pages/expense_settings_page.dart';
import 'pages/expenses_page.dart';

/// `/expenses/**` share one shell branch (the "Expenses" nav entry). Fixed
/// segments are listed before `:expenseId` so they are never read as an id.
List<RouteBase> expenseRoutes() => [
  GoRoute(
    path: '/expenses',
    builder: (context, state) => const ExpensesPage(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const ExpenseFormPage(),
      ),
      GoRoute(
        path: 'settings',
        builder: (context, state) => const ExpenseSettingsPage(),
      ),
      GoRoute(
        path: ':expenseId',
        builder: (context, state) =>
            ExpenseDetailPage(expenseId: state.pathParameters['expenseId']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                ExpenseFormPage(expenseId: state.pathParameters['expenseId']!),
          ),
        ],
      ),
    ],
  ),
];
