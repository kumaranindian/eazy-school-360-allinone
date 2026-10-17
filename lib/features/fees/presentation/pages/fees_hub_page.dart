import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_summary.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';
import '../widgets/fee_widgets.dart';

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

    Widget tile(
      IconData icon,
      String title,
      String description,
      String route,
    ) => HubTile(
      icon: icon,
      title: title,
      description: description,
      onTap: () => context.push(route),
    );

    final can = fee.tenant.can;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Collect',
          subtitle: 'Bills, payments and receipts',
          tiles: [
            if (can(Permission.collectPayments) || can(Permission.viewFees))
              tile(
                Icons.receipt_long_outlined,
                'Invoices',
                'Find an invoice, check its balance, record a payment',
                '/fees/invoices',
              ),
            tile(
              Icons.payments_outlined,
              'Payments & receipts',
              'Every payment taken, with its receipt',
              '/fees/payments',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Set up billing',
          subtitle: 'What is charged, to whom, and when',
          tiles: [
            tile(
              Icons.sell_outlined,
              'Fee structures',
              'Fee heads and amounts for each class',
              '/fees/structures',
            ),
            if (can(Permission.assignFees))
              tile(
                Icons.group_add_outlined,
                'Assign fees',
                'Attach a fee structure to students',
                '/fees/assign',
              ),
            if (can(Permission.issueInvoices))
              tile(
                Icons.playlist_add,
                'Generate invoices',
                'Create invoices for a billing period',
                '/fees/invoices/generate',
              ),
          ],
        ),
        if (can(Permission.viewFeeReports)) ...[
          const SizedBox(height: AppSpacing.md),
          HubGroup(
            title: 'Insights',
            tiles: [
              tile(
                Icons.assessment_outlined,
                'Reports',
                'Collection, dues and defaulters',
                '/fees/reports',
              ),
            ],
          ),
        ],
      ],
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
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            MetricCard(
              label: 'Total invoiced',
              value: Money.format(summary.payableMinor, currency: currency),
              hint: 'after concessions',
            ),
            MetricCard(
              label: 'Collected',
              value: Money.format(summary.collectedMinor, currency: currency),
              hint: rate == null
                  ? null
                  : '${rate.toStringAsFixed(1)}% of collectable',
              color: AppColors.success,
            ),
            MetricCard(
              label: 'Outstanding',
              value: Money.format(summary.outstandingMinor, currency: currency),
            ),
            MetricCard(
              label: 'Overdue',
              value: Money.format(summary.overdueMinor, currency: currency),
              hint: '${summary.overdueInvoiceCount} invoices',
              color: summary.overdueMinor > 0 ? scheme.error : null,
            ),
            MetricCard(
              label: 'Partially paid',
              value: '${summary.partiallyPaidCount}',
              hint: 'invoices',
            ),
            MetricCard(
              label: 'Fully paid',
              value: '${summary.paidCount}',
              hint: 'invoices',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Invoiced ${Money.format(summary.grossMinor, currency: currency)} − concessions ${Money.format(summary.discountMinor, currency: currency)} = '
          '${Money.format(summary.payableMinor, currency: currency)}; waived ${Money.format(summary.waivedMinor, currency: currency)}. '
          'Void invoices and reversed payments are excluded.',
          style: text.bodySmall,
        ),
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
