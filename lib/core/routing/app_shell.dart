import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/notifications/presentation/providers/push_providers.dart';
import '../../features/notifications/presentation/widgets/notification_alerts.dart';
import '../../features/notifications/presentation/widgets/notification_bell.dart';
import '../../shared/branding/page_hero.dart';
import '../../shared/layouts/adaptive_scaffold.dart';
import '../permissions/permission.dart';
import '../permissions/user_role.dart';
import '../tenant/tenant_context.dart';
import '../tenant/tenant_context_provider.dart';
import 'app_routes.dart';
import 'route_titles.dart';

/// Hosts the authenticated area's adaptive navigation around whichever
/// branch (`/dashboard`, `/school`, `/users`) is active. A new top-level
/// authenticated feature only needs a new branch in `app_router.dart` plus
/// an entry in [_allDestinations] — this shell doesn't change.
///
/// Destinations are filtered by [TenantContext.can] against
/// [AppRoutes.requiredPermissions] — a role gains/loses a nav item purely by
/// its `RolePermissions` entry changing; nothing here checks roles.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  /// One entry per [StatefulShellBranch] in `app_router.dart`, in the same
  /// order. Visibility comes from [AppRoutes.requiredPermissions] — the same
  /// map the router enforces — so nav and route access can't drift apart.
  static const _allDestinations = [
    (
      NavDestination(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      AppRoutes.dashboard,
    ),
    (
      NavDestination(
        label: 'School',
        icon: Icons.school_outlined,
        selectedIcon: Icons.school,
      ),
      AppRoutes.school,
    ),
    (
      NavDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
      AppRoutes.settings,
    ),
    (
      NavDestination(
        label: 'Students',
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
      ),
      AppRoutes.students,
    ),
    (
      NavDestination(
        label: 'Parents',
        icon: Icons.family_restroom_outlined,
        selectedIcon: Icons.family_restroom,
      ),
      AppRoutes.parents,
    ),
    (
      NavDestination(
        label: 'Staff',
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
      ),
      AppRoutes.staff,
    ),
    (
      NavDestination(
        label: 'Attendance',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
      ),
      AppRoutes.attendance,
    ),
    (
      NavDestination(
        label: 'Fees',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
      ),
      AppRoutes.fees,
    ),
    (
      NavDestination(
        label: 'My Fees',
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet,
      ),
      AppRoutes.myFees,
    ),
    (
      NavDestination(
        label: 'Leave',
        icon: Icons.event_busy_outlined,
        selectedIcon: Icons.event_busy,
      ),
      AppRoutes.leave,
    ),
    (
      NavDestination(
        label: 'My Leave',
        icon: Icons.beach_access_outlined,
        selectedIcon: Icons.beach_access,
      ),
      AppRoutes.myLeave,
    ),
    (
      NavDestination(
        label: 'Timetable',
        icon: Icons.calendar_view_week_outlined,
        selectedIcon: Icons.calendar_view_week,
      ),
      AppRoutes.timetable,
    ),
    (
      NavDestination(
        label: 'My Timetable',
        icon: Icons.schedule_outlined,
        selectedIcon: Icons.schedule,
      ),
      AppRoutes.myTimetable,
    ),
    (
      NavDestination(
        label: 'Homework',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book,
      ),
      AppRoutes.homework,
    ),
    (
      NavDestination(
        label: 'My Homework',
        icon: Icons.edit_note_outlined,
        selectedIcon: Icons.edit_note,
      ),
      AppRoutes.myHomework,
    ),
    (
      NavDestination(
        label: 'Announcements',
        icon: Icons.campaign_outlined,
        selectedIcon: Icons.campaign,
      ),
      AppRoutes.announcements,
    ),
    (
      NavDestination(
        label: 'Exams',
        icon: Icons.grading_outlined,
        selectedIcon: Icons.grading,
      ),
      AppRoutes.exams,
    ),
    (
      NavDestination(
        label: 'My Results',
        icon: Icons.workspace_premium_outlined,
        selectedIcon: Icons.workspace_premium,
      ),
      AppRoutes.myResults,
    ),
    (
      NavDestination(
        label: 'Notifications',
        icon: Icons.notifications_outlined,
        selectedIcon: Icons.notifications,
      ),
      AppRoutes.notifications,
    ),
    (
      NavDestination(
        label: 'Messages',
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum,
      ),
      AppRoutes.messages,
    ),
    (
      NavDestination(
        label: 'My Profile',
        icon: Icons.account_circle_outlined,
        selectedIcon: Icons.account_circle,
      ),
      AppRoutes.myProfile,
    ),
    (
      NavDestination(
        label: 'Users',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
      ),
      AppRoutes.users,
    ),
  ];

  /// Title, subtitle and icon of each top-level screen's hero. Titles are
  /// descriptive rather than repeating the navigation label.
  static const _heroes = <String, (String, String, IconData)>{
    AppRoutes.school: (
      'School profile',
      'Name, logo and contact details',
      Icons.school_outlined,
    ),
    AppRoutes.settings: (
      'Academic setup',
      'Years, classes, sections, subjects and calendar',
      Icons.tune_outlined,
    ),
    AppRoutes.students: (
      'Student directory',
      'Admissions, profiles and class placement',
      Icons.groups_outlined,
    ),
    AppRoutes.parents: (
      'Parents & guardians',
      'Contacts and linked children',
      Icons.family_restroom_outlined,
    ),
    AppRoutes.staff: (
      'Staff directory',
      'People, departments and designations',
      Icons.badge_outlined,
    ),
    AppRoutes.teachers: (
      'Teaching staff',
      'Who teaches what, and where',
      Icons.co_present_outlined,
    ),
    AppRoutes.attendance: (
      'Daily attendance',
      'Mark, review and report',
      Icons.fact_check_outlined,
    ),
    AppRoutes.fees: (
      'Fees & billing',
      'Structures, invoices, payments and reports',
      Icons.account_balance_wallet_outlined,
    ),
    AppRoutes.myFees: (
      'Dues & receipts',
      'Invoices, payments and receipts',
      Icons.receipt_long_outlined,
    ),
    AppRoutes.leave: (
      'Leave management',
      'Requests, balances and calendar',
      Icons.beach_access_outlined,
    ),
    AppRoutes.myLeave: (
      'Your leave',
      'Requests and balances',
      Icons.event_available_outlined,
    ),
    AppRoutes.timetable: (
      'Class timetables',
      'Periods, rooms and substitutions',
      Icons.calendar_month_outlined,
    ),
    AppRoutes.myTimetable: (
      'Your schedule',
      'Periods and substitutions',
      Icons.schedule_outlined,
    ),
    AppRoutes.homework: (
      'Homework & assignments',
      'Assign, submit and grade',
      Icons.menu_book_outlined,
    ),
    AppRoutes.myHomework: (
      'Your homework',
      'Due work and submissions',
      Icons.edit_note_outlined,
    ),
    AppRoutes.announcements: (
      'Notices',
      'Broadcast to staff, parents and students',
      Icons.campaign_outlined,
    ),
    AppRoutes.exams: (
      'Examinations',
      'Schedules, marks and report cards',
      Icons.workspace_premium_outlined,
    ),
    AppRoutes.myResults: (
      'Your results',
      'Marks and report cards',
      Icons.emoji_events_outlined,
    ),
    AppRoutes.notifications: (
      'Notification centre',
      'Everything that needs your attention',
      Icons.notifications_outlined,
    ),
    AppRoutes.messages: (
      'Parent–teacher messages',
      'Conversations and updates',
      Icons.forum_outlined,
    ),
    AppRoutes.myProfile: (
      'Your profile',
      'Your staff and teaching details',
      Icons.person_outline,
    ),
    AppRoutes.users: (
      'People & access',
      'Accounts, roles and invitations',
      Icons.manage_accounts_outlined,
    ),
  };

  /// The hero for the screen at [path], only when [path] IS a top-level
  /// root (inner screens bring their own app bar). The dashboard draws its
  /// own welcome hero.
  Widget? _heroFor(
    String path,
    TenantContext? tenant, {
    required bool compact,
  }) {
    final key = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final meta = _heroes[key];
    if (meta == null) return null;
    final place = [
      tenant?.school?.name,
      tenant?.branch?.name,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    // Administrators see only reported conversations on this screen (the
    // page itself uses the same title), so the hero says so too.
    final isAdmin =
        tenant != null &&
        (tenant.role == UserRole.schoolAdmin ||
            tenant.role == UserRole.branchAdmin ||
            tenant.role == UserRole.platformAdmin);
    final title = key == AppRoutes.messages && isAdmin
        ? 'Reported conversations'
        : meta.$1;
    return PageHero(
      title: title,
      subtitle: meta.$2,
      compact: compact,
      pills: [if (place.isNotEmpty) HeroPill(place)],
      trailing: PageHero.iconBadge(meta.$3, size: compact ? 32 : 48),
    );
  }

  void _goBranch(int branchIndex) {
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;

    final visibleBranchIndexes = <int>[];
    final visibleDestinations = <NavDestination>[];
    for (
      var branchIndex = 0;
      branchIndex < _allDestinations.length;
      branchIndex++
    ) {
      final (destination, path) = _allDestinations[branchIndex];
      final requiredPermission = AppRoutes.requiredPermissions[path];
      if (requiredPermission == null ||
          (tenant?.can(requiredPermission) ?? false)) {
        visibleBranchIndexes.add(branchIndex);
        visibleDestinations.add(destination);
      }
    }

    final selectedVisibleIndex = visibleBranchIndexes.indexOf(
      navigationShell.currentIndex,
    );

    final path = GoRouterState.of(context).uri.path;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AdaptiveScaffold(
      title: 'EazySchool 360',
      screenTitle: screenTitleForPath(path),
      header: _heroFor(path, tenant, compact: compact),
      destinations: visibleDestinations,
      selectedIndex: selectedVisibleIndex < 0 ? 0 : selectedVisibleIndex,
      onDestinationSelected: (visibleIndex) =>
          _goBranch(visibleBranchIndexes[visibleIndex]),
      body: (tenant?.can(Permission.viewNotifications) ?? false)
          ? NotificationAlerts(child: navigationShell)
          : navigationShell,
      actions: [
        if (tenant?.can(Permission.viewNotifications) ?? false)
          const NotificationBell(),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
          onPressed: () async {
            await unregisterPushDevice(ref);
            await ref.read(authRepositoryProvider).signOut();
          },
        ),
      ],
    );
  }
}
