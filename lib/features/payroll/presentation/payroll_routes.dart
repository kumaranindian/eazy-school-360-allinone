import 'package:go_router/go_router.dart';

import 'pages/pay_components_page.dart';
import 'pages/payroll_page.dart';
import 'pages/payroll_preview_page.dart';
import 'pages/salary_structure_page.dart';

/// `/payroll/**` share one shell branch (the "Payroll" nav entry). Fixed
/// segments are listed before `:staffId` paths.
List<RouteBase> payrollRoutes() => [
  GoRoute(
    path: '/payroll',
    builder: (context, state) => const PayrollPage(),
    routes: [
      GoRoute(
        path: 'components',
        builder: (context, state) => const PayComponentsPage(),
      ),
      GoRoute(
        path: 'preview',
        builder: (context, state) => const PayrollPreviewPage(),
      ),
      GoRoute(
        path: 'staff/:staffId',
        builder: (context, state) =>
            SalaryStructurePage(staffId: state.pathParameters['staffId']!),
      ),
    ],
  ),
];
