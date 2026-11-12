import 'package:go_router/go_router.dart';

import 'pages/admission_dashboard_page.dart';
import 'pages/admission_settings_page.dart';
import 'pages/enquiry_detail_page.dart';
import 'pages/enquiry_form_page.dart';
import 'pages/enquiry_list_page.dart';

/// Admissions (one shell branch). Access is enforced by the router through
/// `AppRoutes.requiredPermissions` (`manageAdmissions`) and, independently,
/// by Firestore rules and the admission Cloud Functions.
List<RouteBase> admissionRoutes() => [
  GoRoute(
    path: '/admissions',
    builder: (context, state) => const AdmissionDashboardPage(),
    routes: [
      GoRoute(
        path: 'settings',
        builder: (context, state) => const AdmissionSettingsPage(),
      ),
      GoRoute(
        path: 'enquiries',
        builder: (context, state) => const EnquiryListPage(),
        routes: [
          // 'new' is declared before ':enquiryId' so it is not read as an id.
          GoRoute(
            path: 'new',
            builder: (context, state) => const EnquiryFormPage(),
          ),
          GoRoute(
            path: ':enquiryId',
            builder: (context, state) => EnquiryDetailPage(
              enquiryId: state.pathParameters['enquiryId']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => EnquiryFormPage(
                  enquiryId: state.pathParameters['enquiryId'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
