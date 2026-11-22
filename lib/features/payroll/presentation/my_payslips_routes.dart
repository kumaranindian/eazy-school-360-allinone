import 'package:go_router/go_router.dart';

import 'pages/my_payslip_page.dart';
import 'pages/my_payslips_page.dart';

/// `/my-payslips/**`: a staff member's own payslips (one shell branch).
List<RouteBase> myPayslipsRoutes() => [
  GoRoute(
    path: '/my-payslips',
    builder: (context, state) => const MyPayslipsPage(),
    routes: [
      GoRoute(
        path: ':branchId/:period',
        builder: (context, state) => MyPayslipPage(
          branchId: state.pathParameters['branchId']!,
          period: state.pathParameters['period']!,
        ),
      ),
    ],
  ),
];
