import '../../../../core/utils/date_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_action_dialogs.dart';
import '../widgets/fee_pdf.dart';
import '../widgets/fee_row_actions.dart';
import '../widgets/fee_widgets.dart';

/// `/fees/invoices/:invoiceId` — the staff view, with actions the signed-in
/// role may take (collect, waive, void, reverse). The parent's read-only view
/// (`/my-fees/invoices/:id`) reuses [InvoiceDetailBody] with `parentView`.
class InvoiceDetailPage extends StatelessWidget {
  final String invoiceId;

  const InvoiceDetailPage({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: InvoiceDetailBody(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          invoiceId: invoiceId,
        ),
      ),
    );
  }
}

class InvoiceDetailBody extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final String invoiceId;
  final bool parentView;

  const InvoiceDetailBody({
    super.key,
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.invoiceId,
    this.parentView = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (schoolId: schoolId, branchId: branchId, invoiceId: invoiceId);
    return AsyncValueWidget(
      value: ref.watch(invoiceProvider(key)),
      errorMessage: userMessageFor,
      onRetry: () => ref.invalidate(invoiceProvider(key)),
      data: (invoice) {
        if (invoice == null) {
          return const EmptyView(
            icon: Icons.receipt_long_outlined,
            message: 'This invoice could not be found.',
          );
        }
        return _Detail(
          tenant: tenant,
          invoice: invoice,
          parentView: parentView,
        );
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  final TenantContext tenant;
  final Invoice invoice;
  final bool parentView;

  const _Detail({
    required this.tenant,
    required this.invoice,
    required this.parentView,
  });

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => FeePdf.invoice(invoice),
        name: invoice.invoiceNumber,
      );
    } catch (error) {
      if (context.mounted) {
        context.showSnackBar(userMessageFor(error), isError: true);
      }
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      await Printing.sharePdf(
        bytes: await FeePdf.invoice(invoice),
        filename: '${invoice.invoiceNumber}.pdf',
      );
    } catch (error) {
      if (context.mounted) {
        context.showSnackBar(userMessageFor(error), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: invoice.schoolId,
      branchId: invoice.branchId,
      invoiceId: invoice.invoiceId,
    );
    final today = FeeDates.todayKey();
    final canCollect =
        !parentView &&
        tenant.can(Permission.collectPayments) &&
        invoice.status.isOpen &&
        invoice.balanceMinor > 0;
    final canWaive =
        !parentView &&
        tenant.can(Permission.grantConcessions) &&
        invoice.status.isOpen &&
        invoice.balanceMinor > 0;
    final canVoid =
        !parentView &&
        tenant.can(Permission.voidInvoices) &&
        !invoice.isVoid &&
        invoice.paidMinor == 0;
    final canReverse = !parentView && tenant.can(Permission.reversePayments);
    final payments = ref.watch(
      invoicePaymentsProvider((
        schoolId: key.schoolId,
        branchId: key.branchId,
        invoiceId: key.invoiceId,
        studentId: invoice.studentId,
      )),
    );
    final receiptRoute = parentView ? '/my-fees/receipts' : '/fees/receipts';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              invoice.invoiceNumber,
              style: context.textStyles.headlineSmall,
            ),
            InvoiceStatusChip(invoice: invoice, todayKey: today),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${invoice.studentName} · ${invoice.admissionNumber} · ${invoice.className} ${invoice.sectionName}'
              .trim(),
        ),
        Text('${invoice.periodLabel} · ${invoice.academicYearName}'),
        Text(
          'Issued ${FeeDates.display(invoice.issueDateKey)} · Due ${FeeDates.display(invoice.dueDateKey)}',
        ),
        if (invoice.createdAt != null)
          Text('Created ${formatInstant(invoice.createdAt)}'),
        if (invoice.isVoid)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Void${invoice.voidReason == null ? '' : ': ${invoice.voidReason}'}',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (canCollect)
              FilledButton.icon(
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Collect payment'),
                onPressed: () => collectPaymentFor(
                  context,
                  tenant: tenant,
                  invoice: invoice,
                ),
              ),
            if (canWaive)
              OutlinedButton.icon(
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: const Text('Waive'),
                onPressed: () => showAdaptiveAppDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => ReasonDialog(
                    title: 'Waive part of the balance',
                    description:
                        'An approved waiver reduces what is owed. It is recorded and cannot be edited.',
                    actionLabel: 'Approve waiver',
                    amountLabel: 'Waiver amount (${invoice.currency})',
                    maxAmountMinor: invoice.balanceMinor,
                    currency: invoice.currency,
                    onConfirm: (reason, amount, _) => ref
                        .read(invoiceRepositoryProvider)
                        .waiveInvoice(
                          invoice: invoice,
                          amountMinor: amount!,
                          reason: reason,
                          actorId: tenant.user.userId,
                        ),
                  ),
                ),
              ),
            if (canVoid)
              OutlinedButton.icon(
                icon: Icon(Icons.block, color: context.colors.error),
                label: Text(
                  'Void invoice',
                  style: TextStyle(color: context.colors.error),
                ),
                onPressed: () => showAdaptiveAppDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => ReasonDialog(
                    title: 'Void this invoice?',
                    description:
                        'The invoice stays on record but no longer counts. Its fees can be billed again on a corrected invoice.',
                    actionLabel: 'Void invoice',
                    destructive: true,
                    onConfirm: (reason, _, __) => ref
                        .read(invoiceRepositoryProvider)
                        .voidInvoice(
                          invoice: invoice,
                          reason: reason,
                          actorId: tenant.user.userId,
                        ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
              onPressed: () => _print(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
              onPressed: () => _download(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Fees', style: context.textStyles.titleMedium),
        Card(
          child: Column(
            children: [
              for (final line in invoice.lines)
                ListTile(
                  dense: true,
                  title: Text(line.name),
                  subtitle: Text(
                    [
                      line.category.displayName,
                      if (line.discountMinor > 0)
                        'Concession ${Money.format(line.discountMinor, currency: invoice.currency)}${line.concessionNote == null ? '' : ' (${line.concessionNote})'}',
                    ].join(' · '),
                  ),
                  trailing: Text(
                    Money.format(line.netMinor, currency: invoice.currency),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                MoneyRow(
                  label: 'Subtotal',
                  amountMinor: invoice.subtotalMinor,
                  currency: invoice.currency,
                ),
                MoneyRow(
                  label: 'Concessions',
                  amountMinor: invoice.discountMinor,
                  currency: invoice.currency,
                  negative: true,
                ),
                MoneyRow(
                  label: 'Payable',
                  amountMinor: invoice.payableMinor,
                  currency: invoice.currency,
                  emphasize: true,
                ),
                if (invoice.waivedMinor > 0)
                  MoneyRow(
                    label: 'Waived',
                    amountMinor: invoice.waivedMinor,
                    currency: invoice.currency,
                    negative: true,
                  ),
                MoneyRow(
                  label: 'Paid',
                  amountMinor: invoice.paidMinor,
                  currency: invoice.currency,
                  negative: true,
                ),
                const Divider(),
                MoneyRow(
                  label: 'Balance due',
                  amountMinor: invoice.balanceMinor,
                  currency: invoice.currency,
                  emphasize: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Payments', style: context.textStyles.titleMedium),
        AsyncValueWidget(
          value: payments,
          errorMessage: userMessageFor,
          data: (list) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('No payments recorded yet.'),
              );
            }
            return Column(
              children: [
                for (final p in list)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${Money.format(p.amountMinor, currency: invoice.currency)} · ${p.methodDisplay}',
                      ),
                      subtitle: Text(
                        '${p.receiptNumber} · ${FeeDates.display(p.paymentDateKey)}${(p.referenceNo ?? '').isEmpty ? '' : ' · Ref ${p.referenceNo}'} · ${p.collectorName} · Recorded ${formatInstant(p.createdAt)}',
                      ),
                      leading: PaymentStatusChip(status: p.status),
                      onTap: () => context.push(
                        '$receiptRoute/${p.paymentId}${parentView ? '?b=${invoice.branchId}' : ''}',
                      ),
                      trailing: canReverse && p.isActive
                          ? IconButton(
                              tooltip: 'Reverse or refund',
                              icon: const Icon(Icons.undo),
                              onPressed: () => _reverse(context, ref, p),
                            )
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _reverse(BuildContext context, WidgetRef ref, Payment payment) {
    return showAdaptiveAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReasonDialog(
        title: 'Reverse or refund ${payment.receiptNumber}?',
        description:
            '${Money.format(payment.amountMinor, currency: invoice.currency)} will be taken off this invoice, which then owes it again. The payment and receipt are kept, marked reversed.',
        actionLabel: 'Confirm',
        destructive: true,
        kinds: ReversalKind.values,
        onConfirm: (reason, _, kind) => ref
            .read(paymentRepositoryProvider)
            .reversePayment(
              payment: payment,
              kind: kind ?? ReversalKind.reversal,
              reason: reason,
              actorId: tenant.user.userId,
            ),
      ),
    );
  }
}
