import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/regional/regional_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import 'staff_home.dart' show HomeAction, homeCanOpen;
import '../../../attendance/domain/parent_attendance_month.dart';
import '../../../attendance/presentation/pages/my_attendance_page.dart';
import '../../../fees/domain/fee_planners.dart';
import '../../../fees/domain/fee_dates.dart';
import '../../../fees/domain/money.dart';
import '../../../fees/presentation/providers/fee_providers.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/parent_providers.dart';
import '../../../students/presentation/providers/selected_child.dart';
import '../../../students/presentation/widgets/child_switcher.dart';

typedef _ChildKey = ({String schoolId, String branchId, String studentId});

class _FeeNow {
  final int balanceMinor;
  final int overdueMinor;
  final String currency;
  const _FeeNow(this.balanceMinor, this.overdueMinor, this.currency);
}

final _childFeeNowProvider = FutureProvider.autoDispose
    .family<_FeeNow, _ChildKey>((ref, key) async {
      final invoices = await ref
          .watch(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      final summary = StudentFeeSummary.of(
        invoices,
        todayKey: FeeDates.todayKey(),
      );
      return _FeeNow(
        summary.balanceMinor,
        summary.overdueMinor,
        invoices.firstOrNull?.currency ??
            ref.read(regionalSettingsProvider).currency,
      );
    });

const _parentActions = [
  HomeAction(
    'My Timetable',
    Icons.calendar_month_outlined,
    AppColors.secondary,
    AppRoutes.myTimetable,
  ),
  HomeAction(
    'My Homework',
    Icons.menu_book_outlined,
    AppColors.accent,
    AppRoutes.myHomework,
  ),
  HomeAction(
    'My Attendance',
    Icons.fact_check_outlined,
    AppColors.success,
    AppRoutes.myAttendance,
  ),
  HomeAction(
    'My Results',
    Icons.emoji_events_outlined,
    AppColors.gold,
    AppRoutes.myResults,
  ),
  HomeAction(
    'My Fees',
    Icons.account_balance_wallet_outlined,
    AppColors.orange,
    AppRoutes.myFees,
  ),
  HomeAction(
    'My Leave',
    Icons.event_available_outlined,
    AppColors.success,
    AppRoutes.myLeave,
  ),
  HomeAction(
    'Messages',
    Icons.forum_outlined,
    AppColors.teal,
    AppRoutes.messages,
  ),
  HomeAction(
    'Notifications',
    Icons.notifications_outlined,
    AppColors.secondary,
    AppRoutes.notifications,
  ),
];

/// A parent's home: the welcome banner, the selected child, this month's
/// attendance and the fee balance at a glance, announcements and quick
/// actions. Each card opens the full screen. Everything shown is read
/// through `firestore.rules`, so a parent only ever gets their own linked
/// children.
class ParentHome extends ConsumerWidget {
  final TenantContext tenant;
  final Widget banner;
  const ParentHome({super.key, required this.tenant, required this.banner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = tenant.school?.schoolId;
    final parentId = tenant.user.linkedParentId;
    if (schoolId == null || parentId == null) {
      return _withBanner(const [
        _Note(
          icon: Icons.link_off,
          text:
              "Your account isn't linked to a parent record yet. Please contact the school office.",
        ),
      ]);
    }
    final key = (schoolId: schoolId, parentId: parentId, branchId: null);
    return ref
        .watch(childrenForParentProvider(key))
        .when(
          loading: () => _withBanner(const [
            Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          ]),
          error: (e, _) => _withBanner([
            _Note(
              icon: Icons.error_outline,
              text: userMessageFor(e),
              onRetry: () => ref.invalidate(childrenForParentProvider),
            ),
          ]),
          data: (children) {
            final child = resolveSelectedChild(
              children,
              ref.watch(selectedChildIdProvider),
            );
            if (child == null) {
              return _withBanner(const [
                _Note(
                  icon: Icons.child_care_outlined,
                  text:
                      'No children are linked to your account with portal access yet.',
                ),
              ]);
            }
            return _Summary(
              tenant: tenant,
              banner: banner,
              children: children,
              child: child,
            );
          },
        );
  }

  Widget _withBanner(List<Widget> rest) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      banner,
      for (final w in rest) ...[const SizedBox(height: AppSpacing.md), w],
    ],
  );
}

class _Summary extends ConsumerWidget {
  final TenantContext tenant;
  final Widget banner;
  final List<Student> children;
  final Student child;
  const _Summary({
    required this.tenant,
    required this.banner,
    required this.children,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = SchoolTime.wallNow();
    final attendance = ref.watch(
      childAttendanceMonthProvider((
        schoolId: child.schoolId,
        branchId: child.branchId,
        studentId: child.studentId,
        year: now.year,
        month: now.month,
      )),
    );
    final fees = tenant.can(AppRoutes.requiredPermissions[AppRoutes.myFees]!)
        ? ref.watch(
            _childFeeNowProvider((
              schoolId: child.schoolId,
              branchId: child.branchId,
              studentId: child.studentId,
            )),
          )
        : null;
    final theme = Theme.of(context);
    final fullName = '${child.firstName} ${child.lastName}';

    final childCard = HomePanel(
      accent: AppColors.accent,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              child.firstName.isEmpty
                  ? '?'
                  : child.firstName.characters.first.toUpperCase(),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Admission No. ${child.admissionNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final attendanceCard = _AttendanceCard(
      month: attendance,
      onTap: () => context.go(AppRoutes.myAttendance),
    );
    final feeCard = fees == null
        ? null
        : _FeeCard(fees: fees, onTap: () => context.go(AppRoutes.myFees));

    final monthLabel = DateFormat('MMM yyyy').format(now);
    final actions = [
      for (final a in _parentActions)
        if (homeCanOpen(tenant, a.path))
          QuickActionTile(
            icon: a.icon,
            label: a.label,
            accent: a.accent,
            onTap: () => context.go(a.path),
          ),
    ];

    return HomeColumns(
      main: [
        banner,
        childCard,
        if (children.length > 1)
          ChildSwitcher(
            children: children,
            selectedId: child.studentId,
            onSelected: ref.read(selectedChildIdProvider.notifier).select,
          ),
        HomeSectionTitle(
          'Quick Overview',
          trailing: Text(
            'This month · $monthLabel',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: attendanceCard),
              if (feeCard != null) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(child: feeCard),
              ],
            ],
          ),
        ),
        if (homeCanOpen(tenant, AppRoutes.announcements))
          PromoStrip(
            icon: Icons.campaign_outlined,
            title: 'School Announcements',
            subtitle: 'New circular, event and updates',
            accent: AppColors.gold,
            onTap: () => context.go(AppRoutes.announcements),
          ),
      ],
      side: [
        if (actions.isNotEmpty) ...[
          const HomeSectionTitle('Quick Actions'),
          QuickActionGrid(tiles: actions),
        ],
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final AsyncValue<ParentAttendanceMonth> month;
  final VoidCallback onTap;
  const _AttendanceCard({required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body = month.when(
      loading: () => const Text('…'),
      error: (_, _) => const Text('Unavailable'),
      data: (m) {
        final pct = m.percentage;
        if (pct == null) {
          return Text('No records yet', style: theme.textTheme.titleMedium);
        }
        final t = m.tally;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: t.attendedDays.round().toString(),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        TextSpan(
                          text: ' / ${t.marked}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text('Days Present', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            ProgressRing(
              fraction: pct / 100,
              label: '${pct.toStringAsFixed(0)}%',
              size: 60,
            ),
          ],
        );
      },
    );
    return HomePanel(
      accent: AppColors.success,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.fact_check_outlined,
            color: AppColors.success,
            size: 26,
          ),
          const SizedBox(height: AppSpacing.xs),
          body,
        ],
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  final AsyncValue<_FeeNow> fees;
  final VoidCallback onTap;
  const _FeeCard({required this.fees, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget status = fees.when(
      loading: () => const Text('…'),
      error: (_, _) => const Text('Unavailable'),
      data: (f) => f.balanceMinor == 0
          ? const StatusPill('All Paid', icon: Icons.check)
          : StatusPill(
              Money.format(f.balanceMinor, currency: f.currency),
              color: f.overdueMinor > 0 ? AppColors.error : AppColors.warning,
            ),
    );
    final overdue = fees.value != null && fees.value!.overdueMinor > 0
        ? '${Money.format(fees.value!.overdueMinor, currency: fees.value!.currency)} overdue'
        : null;
    return HomePanel(
      accent: AppColors.gold,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.gold,
                  size: 26,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Fees',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(alignment: Alignment.centerLeft, child: status),
                if (overdue != null)
                  Text(
                    overdue,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Note({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
