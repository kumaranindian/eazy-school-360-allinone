import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/branding/brand_logo.dart';
import '../../../../shared/branding/page_hero.dart';
import '../../../../shared/loading/async_value_widget.dart';

class _QuickLink {
  final String label;
  final String hint;
  final IconData icon;
  final String path;
  final Color accent;

  const _QuickLink(this.label, this.hint, this.icon, this.path, this.accent);
}

/// Shown only when the signed-in role may open the destination — the same
/// permission map the router and the navigation use.
const _links = [
  _QuickLink(
    'Students',
    'Admissions & profiles',
    Icons.groups_outlined,
    AppRoutes.students,
    AppColors.brandBlue,
  ),
  _QuickLink(
    'Parents',
    'Guardians & logins',
    Icons.family_restroom_outlined,
    AppRoutes.parents,
    AppColors.brandBlueDeep,
  ),
  _QuickLink(
    'Attendance',
    'Mark & review',
    Icons.fact_check_outlined,
    AppRoutes.attendance,
    AppColors.success,
  ),
  _QuickLink(
    'Fees',
    'Invoices & payments',
    Icons.account_balance_wallet_outlined,
    AppRoutes.fees,
    AppColors.orange,
  ),
  _QuickLink(
    'My fees',
    'Dues & receipts',
    Icons.receipt_long_outlined,
    AppRoutes.myFees,
    AppColors.orange,
  ),
  _QuickLink(
    'Timetable',
    'Periods & substitutions',
    Icons.calendar_month_outlined,
    AppRoutes.timetable,
    AppColors.brandBlueDeep,
  ),
  _QuickLink(
    'Homework',
    'Assign & submit',
    Icons.menu_book_outlined,
    AppRoutes.homework,
    AppColors.brandBlue,
  ),
  _QuickLink(
    'Exams',
    'Marks & results',
    Icons.workspace_premium_outlined,
    AppRoutes.exams,
    AppColors.gold,
  ),
  _QuickLink(
    'Leave',
    'Requests & balances',
    Icons.beach_access_outlined,
    AppRoutes.leave,
    AppColors.success,
  ),
  _QuickLink(
    'My leave',
    'Apply & track',
    Icons.event_available_outlined,
    AppRoutes.myLeave,
    AppColors.success,
  ),
  _QuickLink(
    'Staff',
    'People & teachers',
    Icons.badge_outlined,
    AppRoutes.staff,
    AppColors.brandBlueDeep,
  ),
  _QuickLink(
    'Announcements',
    'Notices to everyone',
    Icons.campaign_outlined,
    AppRoutes.announcements,
    AppColors.gold,
  ),
  _QuickLink(
    'Messages',
    'Parents & teachers',
    Icons.forum_outlined,
    AppRoutes.messages,
    AppColors.brandBlue,
  ),
];

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

        final visible = [
          for (final l in _links)
            if (_allowed(tenant, l.path)) l,
        ];

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverToBoxAdapter(child: _Hero(tenant: tenant)),
            ),
            if (visible.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Quick access',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                // Lazy grid: only the visible tiles are built.
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    // A tile's height follows the user's font size: a fixed
                    // extent clips the label and hint as soon as the system
                    // text scale goes above 1.
                    mainAxisExtent: _QuickTile.heightFor(context),
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _QuickTile(link: visible[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static bool _allowed(TenantContext tenant, String path) {
    final needed = AppRoutes.requiredPermissions[path];
    return needed == null || tenant.can(needed);
  }
}

class _Hero extends StatelessWidget {
  final TenantContext tenant;
  const _Hero({required this.tenant});

  @override
  Widget build(BuildContext context) {
    final place = [
      tenant.school?.name,
      tenant.branch?.name,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');

    return PageHero(
      title: 'Welcome, ${tenant.user.name}',
      pills: [
        HeroPill(tenant.role.displayName, filled: true),
        if (place.isNotEmpty) HeroPill(place),
      ],
      trailing: const BrandMark(size: 56, onDark: true),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final _QuickLink link;
  const _QuickTile({required this.link});

  static const double _iconBox = 44;
  static const int _hintLines = 2;

  /// Tallest the tile's text can be (one label line + [_hintLines] hint
  /// lines at the current text scale), never less than the icon box.
  static double heightFor(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.5);

    final content = line(text.titleSmall) + _hintLines * line(text.bodySmall);
    // +2 absorbs sub-pixel rounding in the text layout.
    return (content > _iconBox ? content : _iconBox) + AppSpacing.md * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(link.path),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: link.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(link.icon, color: link.accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      link.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
