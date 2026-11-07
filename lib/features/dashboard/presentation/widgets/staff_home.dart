import '../../../../core/theme/brand_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/regional/school_time.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../leave/domain/leave_enums.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../students/presentation/providers/student_providers.dart';

/// Whether [tenant]'s role may open [path] — the same permission map the
/// router and the navigation use.
bool homeIsAdmin(TenantContext tenant) =>
    tenant.role == UserRole.platformAdmin ||
    tenant.role == UserRole.schoolAdmin ||
    tenant.role == UserRole.branchAdmin;

bool homeCanOpen(TenantContext tenant, String path) {
  final needed = AppRoutes.requiredPermissions[path];
  return needed == null || tenant.can(needed);
}

/// One Quick Actions entry: shown only when the role may open [path].
class HomeAction {
  final String label;
  final IconData icon;
  final Color accent;
  final String path;
  const HomeAction(this.label, this.icon, this.accent, this.path);
}

/// The Quick Actions of an administrator / staff home, in design order.
const _staffActions = [
  HomeAction(
    'Add Student',
    Icons.person_add_alt_1_outlined,
    AppColors.accent,
    AppRoutes.newStudent,
  ),
  HomeAction(
    'Mark Attendance',
    Icons.fact_check_outlined,
    AppColors.success,
    AppRoutes.attendance,
  ),
  HomeAction(
    'Create Announcement',
    Icons.campaign_outlined,
    AppColors.gold,
    AppRoutes.announcementNew,
  ),
  HomeAction(
    'Collect Fees',
    Icons.account_balance_wallet_outlined,
    AppColors.secondary,
    AppRoutes.fees,
  ),
  HomeAction(
    'Add Staff',
    Icons.group_add_outlined,
    AppColors.accent,
    AppRoutes.newStaff,
  ),
  HomeAction(
    'Timetable',
    Icons.calendar_month_outlined,
    AppColors.secondary,
    AppRoutes.timetable,
  ),
  HomeAction(
    'Homework',
    Icons.menu_book_outlined,
    AppColors.teal,
    AppRoutes.homework,
  ),
  HomeAction(
    'Reports',
    Icons.bar_chart_rounded,
    AppColors.secondary,
    AppRoutes.attendanceReports,
  ),
];

/// The home of every non-parent role: headline counts, today's school life,
/// quick actions and a link to reports. Each block is hidden when the role
/// may not open what it leads to, so a teacher or accountant gets the same
/// layout with only their own shortcuts.
class StaffHome extends ConsumerWidget {
  final TenantContext tenant;
  final Widget banner;
  const StaffHome({super.key, required this.tenant, required this.banner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = tenant.school?.schoolId ?? tenant.user.schoolId;
    final branchId = tenant.branch?.branchId ?? tenant.user.branchId;
    // Counts are read school-wide, which the rules allow administrators
    // only (a teacher sees just their sections), so only they get them.
    final hasBranch =
        schoolId != null && branchId != null && homeIsAdmin(tenant);

    final stats = <Widget>[];
    if (hasBranch && homeCanOpen(tenant, AppRoutes.students)) {
      final counts = ref.watch(
        studentCountsProvider((schoolId: schoolId, branchId: branchId)),
      );
      stats.add(
        OverviewStat(
          icon: Icons.groups_outlined,
          value: counts.when(
            data: (m) => '${m[null] ?? 0}',
            loading: () => '…',
            error: (_, _) => '–',
          ),
          label: 'Students',
          accent: context.brandTone(AppColors.accent),
          onTap: () => context.go(AppRoutes.students),
        ),
      );
    }
    if (hasBranch && homeCanOpen(tenant, AppRoutes.parents)) {
      stats.add(
        OverviewStat(
          icon: Icons.family_restroom_outlined,
          value: 'View',
          label: 'Parents',
          accent: AppColors.success,
          onTap: () => context.go(AppRoutes.parents),
        ),
      );
    }
    if (hasBranch && homeCanOpen(tenant, AppRoutes.staff)) {
      final counts = ref.watch(
        staffCountsProvider((
          schoolId: schoolId,
          branchId: branchId,
          teachersOnly: false,
        )),
      );
      stats.add(
        OverviewStat(
          icon: Icons.badge_outlined,
          value: counts.when(
            data: (c) => '${c.total}',
            loading: () => '…',
            error: (_, _) => '–',
          ),
          label: 'Staff',
          accent: context.brandTone(AppColors.secondary),
          onTap: () => context.go(AppRoutes.staff),
        ),
      );
    }

    // Pending leave (students + staff) for those who review it.
    String? pendingLeave;
    if (hasBranch && tenant.can(Permission.reviewLeave)) {
      int? one(LeaveKind kind) => ref
          .watch(
            leavePendingCountProvider((
              schoolId: schoolId,
              branchId: branchId,
              kind: kind,
            )),
          )
          .value;
      final a = one(LeaveKind.student);
      final b = one(LeaveKind.staff);
      pendingLeave = (a == null || b == null) ? '…' : '${a + b} Pending';
    }

    final rows = <InfoRow>[
      if (homeCanOpen(tenant, AppRoutes.attendance))
        InfoRow(
          icon: Icons.check_circle_outline,
          accent: AppColors.success,
          title: 'Attendance',
          subtitle: "Mark or review today's registers",
          onTap: () => context.go(AppRoutes.attendance),
        ),
      if (pendingLeave != null)
        InfoRow(
          icon: Icons.event_note_outlined,
          accent: context.brandTone(AppColors.secondary),
          title: 'Leave Requests',
          subtitle: pendingLeave,
          onTap: () => context.go(AppRoutes.leave),
        ),
      if (homeCanOpen(tenant, AppRoutes.announcements))
        InfoRow(
          icon: Icons.campaign_outlined,
          accent: context.brandTone(AppColors.gold),
          title: 'Announcements',
          subtitle: 'Notices, circulars and drafts',
          onTap: () => context.go(AppRoutes.announcements),
        ),
    ];

    final actions = [
      for (final a in _staffActions)
        if (homeCanOpen(tenant, a.path))
          QuickActionTile(
            icon: a.icon,
            label: a.label,
            accent: a.accent,
            onTap: () => context.go(a.path),
          ),
    ];

    final dateText = DateFormat('EEE, dd MMM').format(SchoolTime.wallNow());

    final overview = <Widget>[
      if (stats.isNotEmpty) ...[
        const HomeSectionTitle('Quick Overview'),
        _StatRow(stats: stats),
      ],
    ];

    final reports = homeCanOpen(tenant, AppRoutes.attendanceReports);

    return HomeColumns(
      main: [
        banner,
        ...overview,
        if (rows.isNotEmpty)
          InfoPanel(
            title: 'Today at School',
            icon: Icons.calendar_today_outlined,
            trailingText: dateText,
            rows: rows,
          ),
      ],
      side: [
        if (actions.isNotEmpty) ...[
          const HomeSectionTitle('Quick Actions'),
          QuickActionGrid(tiles: actions),
        ],
        if (reports)
          PromoStrip(
            icon: Icons.bar_chart_rounded,
            title: 'School Insights',
            subtitle: 'Key performance and trends',
            accent: context.brandTone(AppColors.accent),
            filled: true,
            onTap: () => context.go(AppRoutes.attendanceReports),
          ),
      ],
    );
  }
}

/// Equal-width stat tiles in one row.
class _StatRow extends StatelessWidget {
  final List<Widget> stats;
  const _StatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: stats[i]),
            ],
          ],
        ),
      ),
    );
  }
}
