import 'package:go_router/go_router.dart';

import 'pages/fee_assignment_page.dart';
import 'pages/fee_reports_page.dart';
import 'pages/fee_structures_page.dart';
import 'pages/fees_hub_page.dart';
import 'pages/generate_invoices_page.dart';
import 'pages/invoice_detail_page.dart';
import 'pages/invoices_page.dart';
import 'pages/parent_fees_page.dart';
import 'pages/payments_page.dart';
import 'pages/receipt_page.dart';

/// `/fees/**` share one shell branch (one "Fees" nav entry). Fixed segments
/// (`generate`) are listed before `:invoiceId` so they are never read as an id.
List<RouteBase> feesRoutes() => [
  GoRoute(
    path: '/fees',
    builder: (context, state) => const FeesHubPage(),
    routes: [
      GoRoute(
        path: 'structures',
        builder: (context, state) => const FeeStructuresPage(),
      ),
      GoRoute(
        path: 'assign',
        builder: (context, state) => const FeeAssignmentPage(),
      ),
      GoRoute(
        path: 'invoices',
        builder: (context, state) =>
            InvoicesPage(studentId: state.uri.queryParameters['studentId']),
        routes: [
          GoRoute(
            path: 'generate',
            builder: (context, state) => const GenerateInvoicesPage(),
          ),
          GoRoute(
            path: ':invoiceId',
            builder: (context, state) => InvoiceDetailPage(
              invoiceId: state.pathParameters['invoiceId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: 'payments',
        builder: (context, state) => const PaymentsPage(),
      ),
      GoRoute(
        path: 'receipts/:receiptId',
        builder: (context, state) =>
            ReceiptPage(receiptId: state.pathParameters['receiptId']!),
      ),
      GoRoute(
        path: 'reports',
        builder: (context, state) => const FeeReportsPage(),
      ),
    ],
  ),
];

/// The parent's read-only fee views — their own nav entry.
List<RouteBase> myFeesRoutes() => [
  GoRoute(
    path: '/my-fees',
    builder: (context, state) => const ParentFeesPage(),
    routes: [
      GoRoute(
        path: 'invoices/:invoiceId',
        builder: (context, state) => ParentInvoicePage(
          invoiceId: state.pathParameters['invoiceId']!,
          branchId: state.uri.queryParameters['b'],
        ),
      ),
      GoRoute(
        path: 'receipts/:receiptId',
        builder: (context, state) => ParentReceiptPage(
          receiptId: state.pathParameters['receiptId']!,
          branchId: state.uri.queryParameters['b'],
        ),
      ),
    ],
  ),
];
