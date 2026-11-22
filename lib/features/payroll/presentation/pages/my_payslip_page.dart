import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../domain/payroll_preview.dart';
import '../../domain/payslip_document.dart';
import '../providers/payroll_providers.dart';
import '../widgets/payslip_print.dart';

/// `/my-payslips/:branchId/:period`: one of the signed-in staff member's own
/// payslips, with a PDF to print or save.
class MyPayslipPage extends ConsumerWidget {
  final String branchId;
  final String period;

  const MyPayslipPage({
    super.key,
    required this.branchId,
    required this.period,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = ref.watch(tenantContextProvider).value?.user.schoolId;
    return Scaffold(
      appBar: AppBar(title: Text(periodLabel(period))),
      body: schoolId == null
          ? const Center(child: CircularProgressIndicator())
          : _Slip(schoolId: schoolId, branchId: branchId, period: period),
    );
  }
}

class _Slip extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String period;

  const _Slip({
    required this.schoolId,
    required this.branchId,
    required this.period,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (schoolId: schoolId, branchId: branchId, period: period);
    final loaded = ref.watch(myPayslipProvider(key));
    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(myPayslipProvider(key)),
      ),
      data: (d) => PayslipView(
        doc: d,
        actions: Wrap(
          spacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('payslip-download'),
              onPressed: () => PayslipPrint.download(
                ref,
                d,
                schoolId: schoolId,
                branchId: branchId,
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download PDF'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('payslip-print'),
              onPressed: () => PayslipPrint.print(
                ref,
                d,
                schoolId: schoolId,
                branchId: branchId,
              ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A payslip on screen. Shared by the staff member's own page; the figures
/// come from the stored payslip.
class PayslipView extends StatelessWidget {
  final PayslipDocument doc;
  final Widget? actions;

  const PayslipView({super.key, required this.doc, this.actions});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String money(int v) => Money.format(v, currency: doc.currency);
    Widget row(PayslipDocLine l) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(l.oneOff ? '${l.name} (one-off)' : l.name)),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (l.reduced)
                Text(
                  money(l.plannedMinor),
                  style: text.bodySmall?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(money(l.amountMinor)),
            ],
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(doc.schoolName, style: text.titleMedium),
        if (doc.branchName.isNotEmpty && doc.branchName != doc.schoolName)
          Text(doc.branchName, style: text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Text(doc.staffName, style: text.headlineSmall),
        if (doc.employeeCode.isNotEmpty)
          Text('Employee code ${doc.employeeCode}', style: text.bodySmall),
        Text(
          'Paid ${daysText(doc.paidDays)} of ${doc.workingDays} school days',
          key: const ValueKey('payslip-days'),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings', style: text.titleSmall),
                for (final l in doc.earnings) row(l),
                const Divider(),
                Text('Deductions', style: text.titleSmall),
                if (doc.deductions.isEmpty) const Text('None'),
                for (final l in doc.deductions) row(l),
                const Divider(),
                Row(
                  children: [
                    const Expanded(child: Text('Net pay')),
                    Flexible(
                      child: Text(
                        money(doc.netMinor),
                        key: const ValueKey('payslip-net'),
                        style: text.titleLarge,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (doc.unrecoveredDeductionMinor > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '${money(doc.unrecoveredDeductionMinor)} of deductions could not be taken this month.',
              style: text.bodySmall,
            ),
          ),
        if (doc.paidDate != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Paid on ${doc.paidDate}${doc.paymentModeLabel == null ? '' : ' by ${doc.paymentModeLabel}'}',
              style: text.bodySmall,
            ),
          ),
        if (actions != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: actions!,
          ),
      ],
    );
  }
}
