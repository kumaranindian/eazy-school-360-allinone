import 'package:go_router/go_router.dart';

import 'pages/admission_dashboard_page.dart';
import 'pages/admission_settings_page.dart';
import 'pages/application_form_page.dart';
import 'pages/admission_fees_page.dart';
import 'pages/admission_reports_page.dart';
import 'pages/applications_page.dart';
import 'pages/enquiry_detail_page.dart';
import 'pages/follow_ups_page.dart';
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
        path: 'applications',
        builder: (context, state) => const ApplicationsPage(),
      ),
      GoRoute(
        path: 'fees',
        builder: (context, state) => const AdmissionFeesPage(),
      ),
      GoRoute(
        path: 'reports',
        builder: (context, state) => const AdmissionReportsPage(),
      ),
      GoRoute(
        path: 'follow-ups',
        builder: (context, state) => const FollowUpsPage(),
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
              GoRoute(
                path: 'application/edit',
                builder: (context, state) => ApplicationFormPage(
                  enquiryId: state.pathParameters['enquiryId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
