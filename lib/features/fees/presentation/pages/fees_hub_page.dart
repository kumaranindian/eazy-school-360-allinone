import '../../../../core/theme/brand_theme.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../../shared/error/error_view.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_summary.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';

/// `/fees` — totals for the chosen academic year, from aggregation queries
/// (never a download-and-add), plus the way into each fees screen.
class FeesHubPage extends StatelessWidget {
  const FeesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FeeScope(builder: (context, fee) => _Hub(fee: fee));
  }
}

class _Hub extends ConsumerWidget {
  final FeeContext fee;

  const _Hub({required this.fee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: fee.schoolId,
      branchId: fee.branchId,
      academicYearId: fee.year.academicYearId,
      todayKey: FeeDates.todayKey(),
    );
    final summary = fee.tenant.can(Permission.viewFeeReports)
        ? ref.watch(feeSummaryProvider(key))
        : null;
    final c = fee.currency;

    final can = fee.tenant.can;
    void open(String route) => context.push(route);

    final manage = <_ManageTile>[
      _ManageTile(
        icon: Icons.sell_outlined,
        color: context.brandTone(AppColors.accent),
        title: 'Fee structures',
        subtitle: 'Create & manage fee heads',
        onTap: () => open('/fees/structures'),
      ),
      if (can(Permission.assignFees))
        _ManageTile(
          icon: Icons.group_add_outlined,
          color: AppColors.success,
          title: 'Assign fees',
          subtitle: 'Attach fee heads to students',
          onTap: () => open('/fees/assign'),
        ),
      if (can(Permission.issueInvoices))
        _ManageTile(
          icon: Icons.playlist_add,
          color: context.brandTone(AppColors.secondary),
          title: 'Generate invoices',
          subtitle: 'Create invoices for a billing period',
          onTap: () => open('/fees/invoices/generate'),
        ),
    ];
    final collect = <_NavRow>[
      if (can(Permission.collectPayments) || can(Permission.viewFees))
        _NavRow(
          icon: Icons.receipt_long_outlined,
          color: context.brandTone(AppColors.accent),
          title: 'Invoices',
          subtitle: 'Find, view and manage invoices',
          onTap: () => open('/fees/invoices'),
        ),
      _NavRow(
        icon: Icons.payments_outlined,
        color: context.brandTone(AppColors.accent),
        title: 'Payments & receipts',
        subtitle: 'Record payments and view receipts',
        onTap: () => open('/fees/payments'),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The numbers first: they are what most visits are for.
                if (summary == null)
                  const Text(
                    'Fee totals are available to roles with fee reporting access.',
                  )
                else
                  summary.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => SizedBox(
                      height: 220,
                      child: ErrorView(
                        message: userMessageFor(error),
                        onRetry: () => ref.invalidate(feeSummaryProvider(key)),
                      ),
                    ),
                    data: (s) => _Totals(
                      summary: s,
                      currency: c,
                      yearName: fee.year.name,
                      onRefresh: () => ref.invalidate(feeSummaryProvider(key)),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                const HomeSectionTitle('Manage'),
                const SizedBox(height: AppSpacing.sm),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < manage.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        Expanded(child: manage[i]),
                      ],
                    ],
                  ),
                ),
                if (collect.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const HomeSectionTitle('Collect & track'),
                  const SizedBox(height: AppSpacing.sm),
                  _NavList(rows: collect),
                ],
                if (can(Permission.viewFeeReports)) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const HomeSectionTitle('Insights'),
                  const SizedBox(height: AppSpacing.sm),
                  _NavList(
                    rows: [
                      _NavRow(
                        icon: Icons.bar_chart_rounded,
                        color: context.brandTone(AppColors.accent),
                        title: 'Reports',
                        subtitle: 'Collection, dues and fee summaries',
                        onTap: () => open('/fees/reports'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A square "Manage" tile: coloured icon over a title and one-line hint.
class _ManageTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManageTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: color,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

/// A panel of divided rows, each with an icon tile, title, hint and chevron.
class _NavList extends StatelessWidget {
  final List<_NavRow> rows;
  const _NavList({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: context.brandTone(AppColors.accent),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            InkWell(
              onTap: rows[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: rows[i].color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(rows[i].icon, color: rows[i].color),
                    ),
                    const SizedBox(width: AppSpacing.sm + 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rows[i].title,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            rows[i].subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A headline amount: icon tile, amount and label (the design's 2x2 grid).
class _AmountTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? hint;

  const _AmountTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(label, style: theme.textTheme.bodySmall),
                if (hint != null)
                  Text(
                    hint!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final FeeSummary summary;
  final String currency;
  final String yearName;
  final VoidCallback onRefresh;

  const _Totals({
    required this.summary,
    required this.currency,
    required this.yearName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rate = summary.collectionRate;
    String m(int v) => Money.format(v, currency: currency);
    final upcoming = summary.outstandingMinor - summary.overdueMinor;
    final tiles = [
      _AmountTile(
        icon: Icons.groups_outlined,
        color: context.brandTone(AppColors.accent),
        value: m(summary.payableMinor),
        label: 'Total billed',
        hint: 'after concessions',
      ),
      _AmountTile(
        icon: Icons.check_circle_outline,
        color: AppColors.success,
        value: m(summary.collectedMinor),
        label: 'Total paid',
        hint: rate == null
            ? null
            : '${rate.toStringAsFixed(1)}% of collectable',
      ),
      _AmountTile(
        icon: Icons.volunteer_activism_outlined,
        color: context.brandTone(AppColors.secondary),
        value: m(summary.waivedMinor),
        label: 'Waived',
        hint: 'written off, not collectable',
      ),
      _AmountTile(
        icon: Icons.hourglass_bottom,
        color: context.brandTone(AppColors.gold),
        value: m(summary.outstandingMinor),
        label: 'Balance due',
        hint: 'billed − waived − paid',
      ),
      _AmountTile(
        icon: Icons.warning_amber_rounded,
        color: summary.overdueMinor > 0
            ? scheme.error
            : context.brandTone(AppColors.secondary),
        value: m(summary.overdueMinor),
        label: 'Overdue',
        hint: '${summary.overdueInvoiceCount} invoices past due',
      ),
      _AmountTile(
        icon: Icons.event_outlined,
        color: context.brandTone(AppColors.accent),
        value: m(upcoming),
        label: 'Not yet due',
        hint: 'balance still within due date',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$yearName · ${summary.invoiceCount} invoices',
                style: text.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 2;
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0) const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: i + c < tiles.length
                                ? tiles[i + c]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            StatusPill(
              'Partially paid ${summary.partiallyPaidCount}',
              color: AppColors.warning,
            ),
            StatusPill('Fully paid ${summary.paidCount}'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _Reconciliation(summary: summary, currency: currency),
        if (!summary.isBalanced)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'These figures were read a moment apart and a payment may have arrived in between — refresh. If this persists, the books do not balance and need review.',
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

/// How the headline numbers add up, line by line, so nothing is "missing":
/// invoiced − concessions = billed; billed − waived − paid = balance due.
class _Reconciliation extends StatelessWidget {
  final FeeSummary summary;
  final String currency;

  const _Reconciliation({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String m(int v) => Money.format(v, currency: currency);
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
                  : text.bodyMedium,
            ),
          ),
          Text(
            value,
            style: strong
                ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
                : text.bodyMedium,
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How the numbers add up', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            row('Invoiced (before concessions)', m(summary.grossMinor)),
            row('− Concessions given at billing', m(summary.discountMinor)),
            const Divider(height: AppSpacing.md),
            row('Total billed', m(summary.payableMinor), strong: true),
            row('− Waived', m(summary.waivedMinor)),
            row('− Paid', m(summary.collectedMinor)),
            const Divider(height: AppSpacing.md),
            row('Balance due', m(summary.outstandingMinor), strong: true),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Void invoices and reversed payments are excluded.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
