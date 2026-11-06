import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../widgets/admin/admin_home.dart';
import '../widgets/parent_home_summary.dart';
import '../widgets/staff_home.dart';

/// One shortcut on the dashboard.
///
/// A real shortcut has a [path] and is shown only when the signed-in role may
/// open it (the same permission map the router and the navigation use). A
/// [comingSoon] shortcut is a planned module with no screen yet: it has no
/// path, is shown dimmed with a "Coming soon" badge, and tapping it only says
/// so. [adminsOnly] limits who is shown a planned module.
class _Shortcut {
  final String label;
  final String hint;
  final IconData icon;
  final Color accent;
  final String? path;
  final bool comingSoon;
  final bool adminsOnly;

  const _Shortcut(
    this.label,
    this.hint,
    this.icon,
    this.accent, {
    this.path,
    this.comingSoon = false,
    this.adminsOnly = false,
  });
}

class _Section {
  final String title;
  final String subtitle;
  final List<_Shortcut> items;

  const _Section(this.title, this.subtitle, this.items);
}

/// The dashboard's shortcuts, grouped by purpose like the Settings hub. To add
/// one, add a line here: it appears for every role allowed to open [path].
const _sections = [
  _Section('People', 'Students, families and staff', [
    _Shortcut(
      'Students',
      'Admissions and profiles',
      Icons.groups_outlined,
      AppColors.accent,
      path: AppRoutes.students,
    ),
    _Shortcut(
      'Parents',
      'Guardians and their logins',
      Icons.family_restroom_outlined,
      AppColors.accentDeep,
      path: AppRoutes.parents,
    ),
    _Shortcut(
      'Staff',
      'Staff and teachers',
      Icons.badge_outlined,
      AppColors.accentDeep,
      path: AppRoutes.staff,
    ),
    _Shortcut(
      'My profile',
      'Your staff and teaching details',
      Icons.account_circle_outlined,
      AppColors.accent,
      path: AppRoutes.myProfile,
    ),
  ]),
  _Section('Academics', 'Teaching, learning and results', [
    _Shortcut(
      'Attendance',
      'Mark and review registers',
      Icons.fact_check_outlined,
      AppColors.success,
      path: AppRoutes.attendance,
    ),
    _Shortcut(
      'Timetable',
      'Periods and substitutions',
      Icons.calendar_month_outlined,
      AppColors.accentDeep,
      path: AppRoutes.timetable,
    ),
    _Shortcut(
      'My timetable',
      'Your week at a glance',
      Icons.schedule_outlined,
      AppColors.accentDeep,
      path: AppRoutes.myTimetable,
    ),
    _Shortcut(
      'Homework',
      'Set, review and grade',
      Icons.menu_book_outlined,
      AppColors.accent,
      path: AppRoutes.homework,
    ),
    _Shortcut(
      'My homework',
      'What is due and what you submitted',
      Icons.edit_note_outlined,
      AppColors.accent,
      path: AppRoutes.myHomework,
    ),
    _Shortcut(
      'Exams',
      'Marks, results and report cards',
      Icons.workspace_premium_outlined,
      AppColors.gold,
      path: AppRoutes.exams,
    ),
    _Shortcut(
      'My attendance',
      'Daily record for your children',
      Icons.fact_check_outlined,
      AppColors.accent,
      path: AppRoutes.myAttendance,
    ),
    _Shortcut(
      'My results',
      'Marks and report cards',
      Icons.emoji_events_outlined,
      AppColors.gold,
      path: AppRoutes.myResults,
    ),
  ]),
  _Section('Finance', 'Fees, invoices and receipts', [
    _Shortcut(
      'Fees',
      'Invoices and payments',
      Icons.account_balance_wallet_outlined,
      AppColors.orange,
      path: AppRoutes.fees,
    ),
    _Shortcut(
      'My fees',
      'Dues and receipts',
      Icons.receipt_long_outlined,
      AppColors.orange,
      path: AppRoutes.myFees,
    ),
  ]),
  _Section('Leave', 'Requests, balances and approvals', [
    _Shortcut(
      'Leave',
      'Review requests and balances',
      Icons.beach_access_outlined,
      AppColors.success,
      path: AppRoutes.leave,
    ),
    _Shortcut(
      'My leave',
      'Apply and track',
      Icons.event_available_outlined,
      AppColors.success,
      path: AppRoutes.myLeave,
    ),
  ]),
  _Section('Communication', 'Keep everyone informed', [
    _Shortcut(
      'Announcements',
      'Notices to everyone',
      Icons.campaign_outlined,
      AppColors.gold,
      path: AppRoutes.announcements,
    ),
    _Shortcut(
      'Messages',
      'Parents and teachers',
      Icons.forum_outlined,
      AppColors.accent,
      path: AppRoutes.messages,
    ),
    _Shortcut(
      'Notifications',
      'Alerts and preferences',
      Icons.notifications_outlined,
      AppColors.accent,
      path: AppRoutes.notifications,
    ),
  ]),
  _Section('Administration', 'Set up the school', [
    _Shortcut(
      'School profile',
      'Name, logo and contact details',
      Icons.school_outlined,
      AppColors.accentDeep,
      path: AppRoutes.school,
    ),
    _Shortcut(
      'Academic setup',
      'Years, classes, subjects and calendar',
      Icons.tune_outlined,
      AppColors.accentDeep,
      path: AppRoutes.settings,
    ),
  ]),
  _Section('Account', 'Your own sign-in and data', [
    _Shortcut(
      'Delete account',
      'Ask to delete your account and personal data',
      Icons.delete_outline,
      AppColors.error,
      path: AppRoutes.deleteAccount,
    ),
  ]),
  _Section('Coming soon', 'Planned for a future release', [
    _Shortcut(
      'Transport',
      'Routes, buses and pick-up alerts',
      Icons.directions_bus_outlined,
      AppColors.accent,
      comingSoon: true,
    ),
    _Shortcut(
      'Library',
      'Books, issue and return',
      Icons.local_library_outlined,
      AppColors.accent,
      comingSoon: true,
    ),
    _Shortcut(
      'Events and gallery',
      'School events, photos and RSVPs',
      Icons.celebration_outlined,
      AppColors.accent,
      comingSoon: true,
    ),
    _Shortcut(
      'Admission enquiries',
      'Capture and follow up enquiries',
      Icons.how_to_reg_outlined,
      AppColors.accent,
      comingSoon: true,
      adminsOnly: true,
    ),
    _Shortcut(
      'Payroll',
      'Salaries and payslips',
      Icons.payments_outlined,
      AppColors.accent,
      comingSoon: true,
      adminsOnly: true,
    ),
    _Shortcut(
      'Reports and analytics',
      'School-wide insights',
      Icons.insights_outlined,
      AppColors.accent,
      comingSoon: true,
      adminsOnly: true,
    ),
  ]),
];

bool _isAdmin(UserRole role) =>
    role == UserRole.platformAdmin ||
    role == UserRole.schoolAdmin ||
    role == UserRole.branchAdmin;

bool _visible(TenantContext tenant, _Shortcut item) {
  if (item.adminsOnly && !_isAdmin(tenant.role)) return false;
  final path = item.path;
  if (path == null) return true;
  return _canOpen(tenant, path);
}

bool _canOpen(TenantContext tenant, String path) {
  final needed = AppRoutes.requiredPermissions[path];
  return needed == null || tenant.can(needed);
}

/// The shortcut groups this role may see, empty groups dropped.
List<(_Section, List<_Shortcut>)> _groupsFor(TenantContext tenant) => [
  for (final section in _sections)
    (
      section,
      [
        for (final item in section.items)
          if (_visible(tenant, item)) item,
      ],
    ),
].where((g) => g.$2.isNotEmpty).toList();

Widget _hubGroup(
  BuildContext context,
  _Section section,
  List<_Shortcut> items,
) => HubGroup(
  title: section.title,
  subtitle: section.subtitle,
  tiles: [for (final item in items) _tile(context, item)],
);

Widget _tile(BuildContext context, _Shortcut item) {
  if (item.comingSoon) {
    return HubTile(
      icon: item.icon,
      title: item.label,
      description: item.hint,
      accent: item.accent,
      comingSoon: true,
      onTap: () => _comingSoon(context, item.label),
    );
  }
  return HubTile(
    icon: item.icon,
    title: item.label,
    description: item.hint,
    accent: item.accent,
    onTap: () => context.go(item.path!),
  );
}

void _comingSoon(BuildContext context, String label) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label is coming soon.')));

/// Page body: content centred to a readable width with the standard gutter.
class _HomeScroll extends StatelessWidget {
  final List<Widget> children;
  const _HomeScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant == null) {
          // The router sends a tenant-less account to /create-school
          // before it ever reaches here; this is just the one-frame gap
          // while that redirect takes effect.
          return const SizedBox.shrink();
        }
        final phone = MediaQuery.sizeOf(context).width < 600;
        final isParent = tenant.role == UserRole.parent;
        final place = [
          tenant.school?.name,
          tenant.branch?.name,
        ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');

        final isSchoolAdmin = tenant.role == UserRole.schoolAdmin;
        final email = tenant.user.email;
        final banner = WelcomeBanner(
          name: tenant.user.name,
          roleLabel: tenant.role.displayName,
          // The School Admin's welcome also names the signed-in account.
          subtitle: isParent || place.isEmpty
              ? null
              : (isSchoolAdmin && email.isNotEmpty ? '$email\n$place' : place),
        );

        // On a phone every module lives under the More tab, as in the
        // design; wider screens keep the full grouped list under the home
        // cards, since there is room and no extra tap.
        final groups = phone
            ? const <(_Section, List<_Shortcut>)>[]
            : _groupsFor(tenant);

        final home = isParent
            ? ParentHome(tenant: tenant, banner: banner)
            : isSchoolAdmin
            ? AdminHome(tenant: tenant, banner: banner)
            : StaffHome(tenant: tenant, banner: banner);

        final scroll = _HomeScroll(
          children: [
            home,
            for (final (section, items) in groups) ...[
              const SizedBox(height: AppSpacing.lg),
              _hubGroup(context, section, items),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        );
        // The School Admin's dashboard sits on its own (light) page colour.
        return isSchoolAdmin ? AdminDashboardBackground(child: scroll) : scroll;
      },
    );
  }
}

/// The phone's "More" tab: every module the role may open, grouped as in the
/// Settings hub, plus the planned modules.
class MoreToolsPage extends ConsumerWidget {
  const MoreToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    if (tenant == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return _HomeScroll(
      children: [
        Text(
          'More Tools',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Manage school operations and settings',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (section, items) in _groupsFor(tenant)) ...[
          const SizedBox(height: AppSpacing.lg),
          _hubGroup(context, section, items),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
