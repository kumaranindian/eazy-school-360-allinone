import '../logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/account_inactive_page.dart';
import '../../features/authentication/presentation/pages/change_initial_password_page.dart';
import '../../features/authentication/presentation/providers/initial_password_providers.dart';
import '../../features/authentication/presentation/pages/forgot_password_page.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/register_page.dart';
import '../../features/authentication/presentation/pages/splash_page.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/academic_setup/presentation/academic_setup_routes.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/fees/presentation/fees_routes.dart';
import '../../features/leave/presentation/leave_routes.dart';
import '../../features/timetable/presentation/timetable_routes.dart';
import '../../features/homework/presentation/homework_routes.dart';
import '../../features/announcements/presentation/announcement_routes.dart';
import '../../features/exams/presentation/exam_routes.dart';
import '../../features/notifications/presentation/notification_routes.dart';
import '../../features/communication/presentation/message_routes.dart';
import '../../features/school_setup/presentation/pages/create_school_page.dart';
import '../../features/school_setup/presentation/pages/school_setup_page.dart';
import '../../features/attendance/presentation/attendance_routes.dart';
import '../../features/staff/presentation/staff_routes.dart';
import '../../features/students/presentation/parents_routes.dart';
import '../../features/students/presentation/students_routes.dart';
import '../../features/users/presentation/pages/users_page.dart';
import '../tenant/account_inactive_exception.dart';
import '../tenant/tenant_context_provider.dart';
import 'app_routes.dart';
import 'return_to.dart';
import 'app_shell.dart';

/// Notifies GoRouter to re-run its redirect whenever auth state or tenant
/// context changes — e.g. a sign-out while already on `/dashboard`
/// immediately redirects to `/login`, and a newly-created school
/// immediately redirects away from `/create-school`.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    ref.listen(tenantContextProvider, (_, __) => notifyListeners());
  }
}

/// Route guard chain (see `test/widget/app_router_test.dart` for the cases
/// this is expected to resolve):
///
/// 1. Auth state unresolved → stay on `/` (splash).
/// 2. Signed out → confined to `/login` and `/forgot-password`.
/// 3. Signed in, tenant context still loading → stay on `/` (splash).
/// 4. Signed in, account not ACTIVE (invited/disabled) → confined to
///    `/account-inactive`.
/// 5. Signed in, no profile yet → confined to `/create-school`.
/// 6. Signed in, tenant resolved → kept off the auth/onboarding-only
///    pages, and off any route whose [AppRoutes.requiredPermissions] entry
///    the caller's role lacks.
///
/// This is a UX redirect only — it is not a substitute for Firestore
/// security rules, which remain the real authorization boundary (see
/// SECURITY_ARCHITECTURE.md).
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authStateChangesProvider);
      // fullPath is the route's configured TEMPLATE (e.g.
      // "/students/:studentId"), not the resolved location with real
      // values — required so AppRoutes.requiredPermissions can key a
      // dynamic route by its template. For every static route (no path
      // params) fullPath and matchedLocation are identical, so this is a
      // safe, non-breaking lookup key change for routes that predate
      // Milestone 3 too.
      final path = state.fullPath ?? state.matchedLocation;

      if (!authState.hasValue && !authState.hasError) {
        return path == '/' ? null : ReturnTo.redirect('/', state.uri);
      }

      final isLoggedIn = authState.value != null;
      if (!isLoggedIn) {
        if (path == AppRoutes.login ||
            path == AppRoutes.register ||
            path == AppRoutes.forgotPassword) {
          return null;
        }
        return ReturnTo.redirect(AppRoutes.login, state.uri);
      }

      final tenantState = ref.read(tenantContextProvider);

      if (tenantState.hasError) {
        if (tenantState.error is AccountInactiveException) {
          return path == AppRoutes.accountInactive
              ? null
              : AppRoutes.accountInactive;
        }
        // Any other tenant-loading error: let '/' show it with a retry,
        // rather than the router trying to encode every failure path.
        return path == '/' ? null : ReturnTo.redirect('/', state.uri);
      }

      if (!tenantState.hasValue) {
        return path == '/' ? null : ReturnTo.redirect('/', state.uri);
      }

      final tenant = tenantState.value;
      // Account switch: for a moment the tenant context can still hold the
      // *previous* user's profile while it reloads. Never show or authorise
      // anything from it — wait on the splash until it belongs to this uid.
      if (tenant != null && tenant.user.userId != authState.value!.uid) {
        return path == '/' ? null : ReturnTo.redirect('/', state.uri);
      }
      if (tenant == null) {
        return path == AppRoutes.createSchool
            ? null
            : ReturnTo.redirect(AppRoutes.createSchool, state.uri);
      }

      const signedOutOrOnboardingPaths = {
        '/',
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.forgotPassword,
        AppRoutes.createSchool,
        AppRoutes.accountInactive,
      };
      if (signedOutOrOnboardingPaths.contains(path)) {
        // Back to the page the user was headed for (permissions are checked
        // when that location is redirected in turn).
        return ReturnTo.safe(state.uri.queryParameters[ReturnTo.param]) ??
            AppRoutes.dashboard;
      }

      // First sign-in with an admin-set / derived password: replace it first.
      if (tenant.user.login?.mustChangePassword == true &&
          !ref.read(initialPasswordGateDismissedProvider)) {
        AppLogger.trace(
          'redirect to change-password (mustChangePassword) from $path',
          tag: 'Router',
        );
        return path == AppRoutes.changePassword
            ? null
            : AppRoutes.changePassword;
      }
      if (path == AppRoutes.changePassword) return AppRoutes.dashboard;

      final requiredPermission = AppRoutes.requiredPermissions[path];
      if (requiredPermission != null && !tenant.can(requiredPermission)) {
        AppLogger.trace(
          'redirect to dashboard: role ${tenant.role.wireValue} lacks '
          '$requiredPermission for $path',
          tag: 'Router',
        );
        return AppRoutes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashPage()),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (context, state) => const ChangeInitialPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.accountInactive,
        builder: (context, state) => const AccountInactivePage(),
      ),
      GoRoute(
        path: AppRoutes.createSchool,
        builder: (context, state) => const CreateSchoolPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.school,
                builder: (context, state) => const SchoolSetupPage(),
              ),
            ],
          ),
          StatefulShellBranch(routes: academicSetupRoutes()),
          StatefulShellBranch(routes: studentsRoutes()),
          StatefulShellBranch(routes: parentsRoutes()),
          StatefulShellBranch(routes: staffRoutes()),
          StatefulShellBranch(routes: attendanceRoutes()),
          StatefulShellBranch(routes: feesRoutes()),
          StatefulShellBranch(routes: myFeesRoutes()),
          StatefulShellBranch(routes: leaveRoutes()),
          StatefulShellBranch(routes: myLeaveRoutes()),
          StatefulShellBranch(routes: timetableRoutes()),
          StatefulShellBranch(routes: myTimetableRoutes()),
          StatefulShellBranch(routes: homeworkRoutes()),
          StatefulShellBranch(routes: myHomeworkRoutes()),
          StatefulShellBranch(routes: announcementRoutes()),
          StatefulShellBranch(routes: examRoutes()),
          StatefulShellBranch(routes: myAttendanceRoutes()),
          StatefulShellBranch(routes: myResultsRoutes()),
          StatefulShellBranch(routes: notificationRoutes()),
          StatefulShellBranch(routes: messageRoutes()),
          StatefulShellBranch(routes: myStaffProfileRoutes()),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.users,
                builder: (context, state) => const UsersPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
