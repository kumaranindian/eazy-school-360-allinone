import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/layouts/hub_layout.dart' show HubBadge;
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';

/// Status chip for an invoice; shows "Overdue" (derived from the due date)
/// when an open invoice is past due.
class InvoiceStatusChip extends StatelessWidget {
  final Invoice invoice;
  final String? todayKey;

  const InvoiceStatusChip({super.key, required this.invoice, this.todayKey});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = todayKey ?? FeeDates.todayKey();
    final overdue = invoice.isOverdue(today);
    final color = overdue
        ? scheme.error
        : switch (invoice.status) {
            InvoiceStatus.paid => AppColors.success,
            InvoiceStatus.partiallyPaid => AppColors.warning,
            InvoiceStatus.voided => scheme.outline,
            InvoiceStatus.issued => scheme.primary,
          };
    return Chip(
      label: Text(
        invoice.statusLabel(today),
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

/// Whether a parent could pay [invoice] online once that exists: issued or
/// partly paid, with a balance left.
bool invoiceAwaitsPayment(Invoice invoice) =>
    invoice.status.isOpen && invoice.balanceMinor > 0;

/// The parent's online-payment entry on an invoice that still has a balance:
/// shown dimmed with a "Coming soon" badge; tapping only says so. There is no
/// online payment yet — fees are paid at the school and recorded by staff.
class PayOnlineComingSoon extends StatelessWidget {
  const PayOnlineComingSoon({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () =>
              context.showSnackBar('Online fee payment is coming soon.'),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Pay online'),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
          ),
        ),
        const HubBadge(label: 'Coming soon', icon: Icons.hourglass_top),
      ],
    );
  }
}

class PaymentStatusChip extends StatelessWidget {
  final PaymentStatus status;

  const PaymentStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == PaymentStatus.active
        ? AppColors.success
        : Theme.of(context).colorScheme.error;
    return Chip(
      label: Text(
        status.displayName,
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

/// A label / amount line used in totals blocks.
class MoneyRow extends StatelessWidget {
  final String label;
  final int amountMinor;
  final String currency;
  final bool emphasize;
  final bool negative;

  const MoneyRow({
    super.key,
    required this.label,
    required this.amountMinor,
    required this.currency,
    this.emphasize = false,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            '${negative && amountMinor > 0 ? '− ' : ''}${Money.format(amountMinor, currency: currency)}',
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Key figure tile for dashboards.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          // Brand accent bar: the figure's own colour, else the primary.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: color ?? Theme.of(context).colorScheme.primary,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: color),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hint!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
