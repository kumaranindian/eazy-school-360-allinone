import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
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

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (fee.tenant.can(Permission.collectPayments) ||
                fee.tenant.can(Permission.viewFees))
              FilledButton.icon(
                onPressed: () => context.push('/fees/invoices'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Invoices'),
              ),
            if (fee.tenant.can(Permission.issueInvoices))
              FilledButton.tonalIcon(
                onPressed: () => context.push('/fees/invoices/generate'),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Generate invoices'),
              ),
            if (fee.tenant.can(Permission.assignFees))
              OutlinedButton.icon(
                onPressed: () => context.push('/fees/assign'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Assign fees'),
              ),
            OutlinedButton.icon(
              onPressed: () => context.push('/fees/structures'),
              icon: const Icon(Icons.sell_outlined),
              label: const Text('Fee structures'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/fees/payments'),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Payments & receipts'),
            ),
            if (fee.tenant.can(Permission.viewFeeReports))
              OutlinedButton.icon(
                onPressed: () => context.push('/fees/reports'),
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('Reports'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
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
