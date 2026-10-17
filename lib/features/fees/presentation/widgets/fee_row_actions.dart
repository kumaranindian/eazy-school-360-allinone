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
import '../../domain/invoice.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import 'fee_action_dialogs.dart';
import 'fee_pdf.dart';

/// Whether [tenant] may take a payment against [invoice] right now: they hold
/// the permission, and the invoice is open with something still owing.
bool canCollectPayment(TenantContext tenant, Invoice invoice) =>
    tenant.can(Permission.collectPayments) &&
    invoice.status.isOpen &&
    invoice.balanceMinor > 0;

/// Opens the Collect payment dialog for [invoice]; once the payment is
/// recorded, says so and opens its receipt (where it can be printed). The one
/// implementation behind the invoice page's button and the list's.
Future<void> collectPaymentFor(
  BuildContext context, {
  required TenantContext tenant,
  required Invoice invoice,
}) async {
  final result = await showAdaptiveAppDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CollectPaymentDialog(
      schoolId: invoice.schoolId,
      branchId: invoice.branchId,
      collectorId: tenant.user.userId,
      collectorName: tenant.user.name,
      invoice: invoice,
    ),
  );
  if (result != null && context.mounted) {
    context.showSnackBar('Payment recorded successfully.');
    context.push('/fees/receipts/$result');
  }
}

/// Prints the receipt of [payment] straight from a list: loads the receipt the
/// receipt page would show and hands it to the print dialog.
Future<void> printReceiptFor(
  BuildContext context,
  WidgetRef ref, {
  required Payment payment,
}) async {
  try {
    final receipt = await ref
        .read(paymentRepositoryProvider)
        .getReceipt(payment.schoolId, payment.branchId, payment.paymentId);
    if (receipt == null) {
      if (context.mounted) {
        context.showSnackBar('This receipt could not be found.', isError: true);
      }
      return;
    }
    await Printing.layoutPdf(
      onLayout: (_) => FeePdf.receipt(receipt),
      name: receipt.receiptNumber,
    );
  } catch (error) {
    if (context.mounted) {
      context.showSnackBar(userMessageFor(error), isError: true);
    }
  }
}

/// The actions at the end of an invoice row: take a payment (when one can be
/// taken) and open the invoice.
class InvoiceRowActions extends StatelessWidget {
  final Invoice invoice;
  final TenantContext tenant;

  const InvoiceRowActions({
    super.key,
    required this.invoice,
    required this.tenant,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canCollectPayment(tenant, invoice)) ...[
          FilledButton.tonalIcon(
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Collect'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 34),
            ),
            onPressed: () =>
                collectPaymentFor(context, tenant: tenant, invoice: invoice),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 34),
          ),
          onPressed: () => context.push('/fees/invoices/${invoice.invoiceId}'),
          child: const Text('View'),
        ),
      ],
    );
  }
}

/// The actions at the end of a payment row: open the receipt, or print it.
class PaymentRowActions extends ConsumerWidget {
  final Payment payment;

  const PaymentRowActions({super.key, required this.payment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 34),
          ),
          onPressed: () => context.push('/fees/receipts/${payment.paymentId}'),
          child: const Text('Receipt'),
        ),
        IconButton(
          tooltip: 'Print receipt',
          icon: const Icon(Icons.print_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => printReceiptFor(context, ref, payment: payment),
        ),
      ],
    );
  }
}

/// The first cell of an invoice row: the number (a visible link that opens the
/// invoice) with **Collect** right beside it when a payment can be taken. It
/// sits in the first column on purpose: a wide table scrolls sideways, and an
/// action in the last column would be off screen.
class InvoiceNumberCell extends StatelessWidget {
  final Invoice invoice;
  final TenantContext tenant;

  const InvoiceNumberCell({
    super.key,
    required this.invoice,
    required this.tenant,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => context.push('/fees/invoices/${invoice.invoiceId}'),
          child: Text(
            invoice.invoiceNumber,
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        ),
        if (canCollectPayment(tenant, invoice)) ...[
          const SizedBox(width: AppSpacing.sm),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Collect'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 34),
            ),
            onPressed: () =>
                collectPaymentFor(context, tenant: tenant, invoice: invoice),
          ),
        ],
      ],
    );
  }
}

/// The first cell of a payment row: the receipt number (a visible link that
/// opens the receipt) with **Print** right beside it.
class ReceiptNumberCell extends ConsumerWidget {
  final Payment payment;

  const ReceiptNumberCell({super.key, required this.payment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => context.push('/fees/receipts/${payment.paymentId}'),
          child: Text(
            payment.receiptNumber,
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Print receipt',
          icon: const Icon(Icons.print_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => printReceiptFor(context, ref, payment: payment),
        ),
      ],
    );
  }
}
