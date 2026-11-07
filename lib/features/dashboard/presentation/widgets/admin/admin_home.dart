import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_version.dart';
import '../../../../../core/permissions/permission.dart';
import '../../../../../core/regional/regional_providers.dart';
import '../../../../../core/regional/school_time.dart';
import '../../../../../core/routing/app_routes.dart';
import '../../../../../core/tenant/tenant_context.dart';
import '../../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../leave/domain/leave_enums.dart';
import '../../../../leave/presentation/providers/leave_providers.dart';
import '../../../../staff/presentation/providers/staff_providers.dart';
import '../../providers/admin_dashboard_providers.dart';
import 'admin_dashboard_widgets.dart';
import 'admin_summary_cards.dart';

/// Width at which the dashboard goes two-up, and the width of the content
/// column on large screens.
abstract final class AdminDashboardBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;
  static const double maxContentWidth = 1200;
}

class _Action {
  final String label;
  final IconData icon;
  final Color Function(AdminDashboardPalette) color;
  final String path;
  const _Action(this.label, this.icon, this.color, this.path);
}

/// The eight quick actions, in design order. Each opens an existing route and
/// is shown only when the role may open it (the router's permission map).
final _actions = <_Action>[
  _Action(
    'Add Student',
    Icons.person_add_alt_1_outlined,
    (p) => p.primary,
    AppRoutes.newStudent,
  ),
  _Action(
    'Mark Attendance',
    Icons.fact_check_outlined,
    (p) => p.success,
    AppRoutes.attendance,
  ),
  _Action(
    'Create Announcement',
    Icons.campaign_outlined,
    (p) => p.warning,
    AppRoutes.announcementNew,
  ),
  _Action(
    'Collect Fees',
    Icons.account_balance_wallet_outlined,
    (p) => p.purple,
    AppRoutes.fees,
  ),
  _Action(
    'Add Staff',
    Icons.group_add_outlined,
    (p) => p.primary,
    AppRoutes.newStaff,
  ),
  _Action(
    'Timetable',
    Icons.calendar_month_outlined,
    (p) => p.purple,
    AppRoutes.timetable,
  ),
  _Action(
    'Homework',
    Icons.menu_book_outlined,
    (p) => p.teal,
    AppRoutes.homework,
  ),
  _Action(
    'Reports',
    Icons.bar_chart_rounded,
    (p) => p.warning,
    AppRoutes.attendanceReports,
  ),
];

bool _can(TenantContext t, String path) {
  final needed = AppRoutes.requiredPermissions[path];
  return needed == null || t.can(needed);
}

/// The School Admin's home: overview counts, today's attendance, fee
/// collection, today at school, quick actions, insights and footer.
///
/// Data comes from the existing providers (student/staff counts, attendance
/// registers, fee reports, pending leave) plus one parent count; every block
/// handles loading, error and empty states and hides when the role may not
/// open what it leads to.
class AdminHome extends ConsumerWidget {
  final TenantContext tenant;
  final Widget banner;
  const AdminHome({super.key, required this.tenant, required this.banner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AdminDashboardPalette.of(context);
    final schoolId = tenant.school?.schoolId ?? tenant.user.schoolId;
    final branchId = tenant.branch?.branchId ?? tenant.user.branchId;
    final hasBranch = schoolId != null && branchId != null;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final tablet = w >= AdminDashboardBreakpoints.tablet;
        final desktop = w >= AdminDashboardBreakpoints.desktop;
        const gap = AdminDashboardPalette.gap;

        final blocks = <Widget>[
          banner,
          if (hasBranch) ...[
            _overview(context, ref, schoolId, branchId),
            _middle(context, ref, schoolId, branchId, tablet, desktop),
          ],
          _actionsBlock(context, w, p),
          if (_can(tenant, AppRoutes.attendanceReports))
            AdminInsightsBanner(
              onTap: () => context.go(AppRoutes.attendanceReports),
            ),
          AdminFooter(
            schoolName: tenant.school?.name,
            versionLabel: appVersionLabel,
          ),
        ];

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AdminDashboardBreakpoints.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  blocks[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _overview(
    BuildContext context,
    WidgetRef ref,
    String schoolId,
    String branchId,
  ) {
    final p = AdminDashboardPalette.of(context);
    final key = (schoolId: schoolId, branchId: branchId);
    final cards = <Widget>[];

    Widget card({
      required IconData icon,
      required Color color,
      required String label,
      required AsyncValue<int> value,
      required String path,
      required VoidCallback retry,
    }) => AdminOverviewCard(
      icon: icon,
      color: color,
      label: label,
      value: value.value,
      loading: value.isLoading && !value.hasValue,
      error: value.hasError && !value.hasValue,
      onTap: () => context.go(path),
      onRetry: retry,
    );

    if (_can(tenant, AppRoutes.students)) {
      cards.add(
        card(
          icon: Icons.groups_outlined,
          color: p.primary,
          label: 'Students',
          value: ref.watch(dashboardStudentCountProvider(key)),
          path: AppRoutes.students,
          retry: () => ref.invalidate(dashboardStudentCountProvider(key)),
        ),
      );
    }
    if (_can(tenant, AppRoutes.parents)) {
      cards.add(
        card(
          icon: Icons.family_restroom_outlined,
          color: p.success,
          label: 'Parents',
          value: ref.watch(dashboardParentCountProvider(key)),
          path: AppRoutes.parents,
          retry: () => ref.invalidate(dashboardParentCountProvider(key)),
        ),
      );
    }
    if (_can(tenant, AppRoutes.staff)) {
      final staff = ref.watch(
        staffCountsProvider((
          schoolId: schoolId,
          branchId: branchId,
          teachersOnly: false,
        )),
      );
      cards.add(
        card(
          icon: Icons.badge_outlined,
          color: p.purple,
          label: 'Staff',
          value: staff.whenData((s) => s.active),
          path: AppRoutes.staff,
          retry: () => ref.invalidate(staffCountsProvider),
        ),
      );
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeading('Quick Overview'),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _middle(
    BuildContext context,
    WidgetRef ref,
    String schoolId,
    String branchId,
    bool tablet,
    bool desktop,
  ) {
    final key = (schoolId: schoolId, branchId: branchId);
    final regional = ref.watch(regionalSettingsProvider);
    final panels = <Widget>[];

    if (_can(tenant, AppRoutes.attendance)) {
      final a = ref.watch(attendanceTodayProvider(key));
      final year = ref.watch(dashboardYearProvider(key));
      panels.add(
        AttendanceSummaryCard(
          data: a.value,
          loading: a.isLoading && !a.hasValue,
          error: a.hasError && !a.hasValue,
          noYear: year.hasValue && year.value == null,
          onOpen: () => context.go(AppRoutes.attendance),
          onRetry: () => ref.invalidate(attendanceTodayProvider(key)),
        ),
      );
    }
    if (_can(tenant, AppRoutes.fees)) {
      final f = ref.watch(feeMonthCardProvider(key));
      final year = ref.watch(dashboardYearProvider(key));
      panels.add(
        FeeCollectionCard(
          data: f.value,
          currency: regional.currency,
          loading: f.isLoading && !f.hasValue,
          error: f.hasError && !f.hasValue,
          noYear: year.hasValue && year.value == null,
          onOpen: () => context.go(AppRoutes.fees),
          onRetry: () => ref.invalidate(feeMonthCardProvider(key)),
        ),
      );
    }
    final today = _todayPanel(context, ref, schoolId, branchId);
    if (today != null) panels.add(today);
    if (panels.isEmpty) return const SizedBox.shrink();

    final perRow = desktop ? 3 : (tablet ? 2 : 1);
    const gap = AdminDashboardPalette.gap;
    final rows = <Widget>[];
    for (var i = 0; i < panels.length; i += perRow) {
      final slice = panels.sublist(
        i,
        (i + perRow) > panels.length ? panels.length : i + perRow,
      );
      rows.add(
        perRow == 1
            ? slice.first
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < perRow; j++) ...[
                      if (j > 0) const SizedBox(width: gap),
                      Expanded(
                        child: j < slice.length
                            ? slice[j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }

  Widget? _todayPanel(
    BuildContext context,
    WidgetRef ref,
    String schoolId,
    String branchId,
  ) {
    final p = AdminDashboardPalette.of(context);
    int? pendingLeave;
    var leaveLoading = false;
    if (tenant.can(Permission.reviewLeave)) {
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
      if (a == null || b == null) {
        leaveLoading = true;
      } else {
        pendingLeave = a + b;
      }
    }
    final rows = <Widget>[
      if (_can(tenant, AppRoutes.attendance))
        AdminActivityRow(
          icon: Icons.check_circle_outline,
          color: p.success,
          title: 'Attendance',
          subtitle: "Mark or review today's registers",
          onTap: () => context.go(AppRoutes.attendance),
        ),
      if (tenant.can(Permission.reviewLeave))
        AdminActivityRow(
          icon: Icons.event_note_outlined,
          color: p.purple,
          title: 'Leave Requests',
          subtitle: leaveLoading
              ? 'Checking…'
              : (pendingLeave == 0
                    ? 'No pending requests'
                    : '$pendingLeave pending'),
          pending: pendingLeave,
          onTap: () => context.go(AppRoutes.leave),
        ),
      if (_can(tenant, AppRoutes.announcements))
        AdminActivityRow(
          icon: Icons.campaign_outlined,
          color: p.warning,
          title: 'Announcements',
          subtitle: 'Notices, circulars and drafts',
          onTap: () => context.go(AppRoutes.announcements),
        ),
    ];
    if (rows.isEmpty) return null;
    return AdminCard(
      semanticLabel: 'Today at school',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeading(
            'Today at School',
            trailing: Text(
              _dateText(),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            rows[i],
          ],
        ],
      ),
    );
  }

  String _dateText() {
    final d = SchoolTime.wallNow();
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${wd[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${mo[d.month - 1]}';
  }

  Widget _actionsBlock(
    BuildContext context,
    double width,
    AdminDashboardPalette p,
  ) {
    final tiles = [
      for (final a in _actions)
        if (_can(tenant, a.path))
          AdminActionTile(
            icon: a.icon,
            color: a.color(p),
            label: a.label,
            onTap: () => context.go(a.path),
          ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    final cols = width >= AdminDashboardBreakpoints.desktop
        ? 8
        : width >= AdminDashboardBreakpoints.tablet
        ? 4
        : (width >= 400 ? 4 : 2);
    const spacing = 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeading('Quick Actions'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final tileW = (c.maxWidth - spacing * (cols - 1)) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final t in tiles) SizedBox(width: tileW, child: t),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Page background for the admin dashboard (light design; dark mode keeps
/// the app's own surface).
class AdminDashboardBackground extends StatelessWidget {
  final Widget child;
  const AdminDashboardBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return ColoredBox(
      color: p.background,
      child: SizedBox.expand(child: child),
    );
  }
}
