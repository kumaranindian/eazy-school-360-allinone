import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import 'fee_widgets.dart';

typedef StudentFeesKey = ({String schoolId, String branchId, String studentId});

typedef StudentFeesData = ({List<Invoice> invoices, List<Payment> payments});

/// One student's invoices and payments (all academic years). Reloads when a
/// fee action elsewhere calls `notifyFeeDataChanged`.
final studentFeesProvider = FutureProvider.autoDispose
    .family<StudentFeesData, StudentFeesKey>((ref, key) async {
      ref.watch(feeDataVersionProvider);
      final invoices = ref
          .read(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      final payments = ref
          .read(paymentRepositoryProvider)
          .fetchStudentPayments(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      return (invoices: await invoices, payments: await payments);
    }, retry: (retryCount, error) => null);

/// The "Fees" tab of the student profile: what was billed, paid and is still
/// owed, every invoice (grouped by academic year) and the payment history.
/// Read-only; invoices and receipts open their own pages for actions.
class StudentFeesTab extends ConsumerWidget {
  final StudentFeesKey studentKey;

  const StudentFeesTab({super.key, required this.studentKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentFeesProvider(studentKey));
    final currency = ref.watch(regionalSettingsProvider).currency;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(studentFeesProvider(studentKey)),
      ),
      data: (data) {
        if (data.invoices.isEmpty && data.payments.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: EmptyView(
              icon: Icons.receipt_long_outlined,
              message: 'No invoices have been generated for this student yet.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentFeesProvider(studentKey));
            await ref.read(studentFeesProvider(studentKey).future);
          },
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _Summary(invoices: data.invoices, currency: currency),
                  const SizedBox(height: AppSpacing.md),
                  _InvoicesByYear(invoices: data.invoices, currency: currency),
                  const SizedBox(height: AppSpacing.md),
                  _PaymentHistory(payments: data.payments, currency: currency),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _money(int v, String currency) => Money.format(v, currency: currency);

class _Summary extends StatelessWidget {
  final List<Invoice> invoices;
  final String currency;

  const _Summary({required this.invoices, required this.currency});

  @override
  Widget build(BuildContext context) {
    final s = StudentFeeSummary.of(invoices, todayKey: FeeDates.todayKey());
    final scheme = Theme.of(context).colorScheme;
    final tiles = <(String, int, Color?)>[
      ('Billed', s.payableMinor, null),
      ('Paid', s.paidMinor, null),
      ('Waived', s.waivedMinor, null),
      ('Balance due', s.balanceMinor, s.balanceMinor > 0 ? scheme.error : null),
      ('Overdue', s.overdueMinor, s.overdueMinor > 0 ? scheme.error : null),
      ('Upcoming', s.upcomingMinor, null),
    ];
    // Two columns on phones, three on tablets, six on wide screens.
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 840 ? 6 : (c.maxWidth >= 520 ? 3 : 2);
        const gap = AppSpacing.sm;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: _Tile(
                  label: t.$1,
                  value: _money(t.$2, currency),
                  color: t.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Tile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesByYear extends StatelessWidget {
  final List<Invoice> invoices;
  final String currency;

  const _InvoicesByYear({required this.invoices, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (invoices.isEmpty) {
      return Text('No invoices yet.', style: theme.textTheme.bodyMedium);
    }
    final byYear = <String, List<Invoice>>{};
    final names = <String, String>{};
    for (final i in invoices) {
      byYear.putIfAbsent(i.academicYearId, () => []).add(i);
      names[i.academicYearId] = i.academicYearName;
    }
    final years = byYear.keys.toList()
      ..sort((a, b) => (names[b] ?? b).compareTo(names[a] ?? a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invoices', style: theme.textTheme.titleMedium),
        for (final y in years) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Academic year ${names[y] ?? y}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final i
              in (byYear[y]!
                ..sort((a, b) => b.dueDateKey.compareTo(a.dueDateKey))))
            _InvoiceCard(invoice: i, currency: currency),
        ],
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final String currency;

  const _InvoiceCard({required this.invoice, required this.currency});

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final theme = Theme.of(context);
    final cls = '${i.className} ${i.sectionName}'.trim();
    Widget figure(String label, int v, {bool strong = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          _money(v, currency),
          style: strong
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodyMedium,
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/fees/invoices/${i.invoiceId}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(i.invoiceNumber, style: theme.textTheme.titleSmall),
                  InvoiceStatusChip(invoice: i),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [
                  i.periodLabel,
                  if (cls.isNotEmpty) cls,
                  'Due ${FeeDates.display(i.dueDateKey)}',
                ].join('  •  '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (i.lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    children: [
                      for (final l in i.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  l.name,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                _money(l.netMinor, currency),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  figure('Payable', i.payableMinor),
                  if (i.waivedMinor > 0) figure('Waived', i.waivedMinor),
                  figure('Paid', i.paidMinor),
                  figure('Balance', i.balanceMinor, strong: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentHistory extends StatelessWidget {
  final List<Payment> payments;
  final String currency;

  const _PaymentHistory({required this.payments, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...payments]
      ..sort((a, b) => b.paymentDateKey.compareTo(a.paymentDateKey));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payments', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        if (sorted.isEmpty)
          Text('No payments recorded yet.', style: theme.textTheme.bodyMedium)
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var n = 0; n < sorted.length; n++) ...[
                  if (n > 0) const Divider(height: 1),
                  ListTile(
                    onTap: () =>
                        context.push('/fees/receipts/${sorted[n].paymentId}'),
                    title: Text(
                      _money(sorted[n].amountMinor, currency),
                      style: sorted[n].status == PaymentStatus.reversed
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: Text(
                      '${FeeDates.display(sorted[n].paymentDateKey)}  •  '
                      '${sorted[n].methodDisplay}  •  '
                      '${sorted[n].receiptNumber}  •  ${sorted[n].invoiceNumber}',
                    ),
                    trailing: sorted[n].status == PaymentStatus.reversed
                        ? PaymentStatusChip(status: sorted[n].status)
                        : const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
