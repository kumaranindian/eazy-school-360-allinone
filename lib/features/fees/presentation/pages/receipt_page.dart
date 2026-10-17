import '../../../../core/utils/date_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/fee_dates.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_pdf.dart';

/// `/fees/receipts/:receiptId` (staff) and `/my-fees/receipts/:id?b=<branch>`
/// (parent, read-only). A reversed payment's receipt is kept and shown as
/// reversed, with the reversal record when the viewer may read it.
class ReceiptPage extends StatelessWidget {
  final String receiptId;

  const ReceiptPage({super.key, required this.receiptId});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: ReceiptBody(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          receiptId: receiptId,
        ),
      ),
    );
  }
}

class ReceiptBody extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final String receiptId;

  const ReceiptBody({
    super.key,
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.receiptId,
  });

  @override
  ConsumerState<ReceiptBody> createState() => _ReceiptBodyState();
}

class _ReceiptBodyState extends ConsumerState<ReceiptBody> {
  late Future<({Receipt? receipt, PaymentReversal? reversal})> _future =
      _load();

  Future<({Receipt? receipt, PaymentReversal? reversal})> _load() async {
    final repo = ref.read(paymentRepositoryProvider);
    final receipt = await repo.getReceipt(
      widget.schoolId,
      widget.branchId,
      widget.receiptId,
    );
    PaymentReversal? reversal;
    if (receipt != null &&
        receipt.isReversed &&
        widget.tenant.can(Permission.viewFees)) {
      reversal = await repo.getReversal(
        widget.schoolId,
        widget.branchId,
        widget.receiptId,
      );
    }
    return (receipt: receipt, reversal: reversal);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorView(
            message: userMessageFor(snapshot.error!),
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final receipt = snapshot.data!.receipt;
        if (receipt == null) {
          return const EmptyView(
            icon: Icons.receipt_outlined,
            message: 'This receipt could not be found.',
          );
        }
        final reversal = snapshot.data!.reversal;
        final scheme = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (receipt.isReversed)
                      Card(
                        color: scheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            reversal == null
                                ? 'This payment was reversed. The receipt is kept for the record.'
                                : '${reversal.kind.displayName} on ${FeeDates.display(reversal.reversalDateKey)}: ${reversal.reason}',
                          ),
                        ),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              receipt.schoolName,
                              style: context.textStyles.titleLarge,
                            ),
                            if (receipt.branchName.isNotEmpty)
                              Text(receipt.branchName),
                            const Divider(height: AppSpacing.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Payment receipt',
                                    style: context.textStyles.titleMedium,
                                  ),
                                ),
                                Text(
                                  receipt.receiptNumber,
                                  style: context.textStyles.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _row('Received from', receipt.studentName),
                            _row('Admission no.', receipt.admissionNumber),
                            _row(
                              'Class',
                              '${receipt.className} ${receipt.sectionName}'
                                  .trim(),
                            ),
                            _row('Academic year', receipt.academicYearName),
                            _row(
                              'Invoice',
                              '${receipt.invoiceNumber} · ${receipt.periodLabel}',
                            ),
                            _row(
                              'Payment date',
                              FeeDates.display(receipt.paymentDateKey),
                            ),
                            _row(
                              'Recorded on',
                              formatInstant(receipt.createdAt),
                            ),
                            _row('Method', receipt.methodDisplay),
                            if ((receipt.referenceNo ?? '').isNotEmpty)
                              _row('Reference', receipt.referenceNo!),
                            const Divider(),
                            _row(
                              'Amount received',
                              Money.format(
                                receipt.amountMinor,
                                currency: receipt.currency,
                              ),
                              bold: true,
                            ),
                            _row(
                              'Balance after payment',
                              Money.format(
                                receipt.balanceAfterMinor,
                                currency: receipt.currency,
                              ),
                            ),
                            const Divider(),
                            _row('Collected by', receipt.collectorName),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print'),
                          onPressed: () async {
                            try {
                              await Printing.layoutPdf(
                                onLayout: (_) => FeePdf.receipt(receipt),
                                name: receipt.receiptNumber,
                              );
                            } catch (error) {
                              if (context.mounted) {
                                context.showSnackBar(
                                  userMessageFor(error),
                                  isError: true,
                                );
                              }
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download PDF'),
                          onPressed: () async {
                            try {
                              await Printing.sharePdf(
                                bytes: await FeePdf.receipt(receipt),
                                filename: '${receipt.receiptNumber}.pdf',
                              );
                            } catch (error) {
                              if (context.mounted) {
                                context.showSnackBar(
                                  userMessageFor(error),
                                  isError: true,
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}
