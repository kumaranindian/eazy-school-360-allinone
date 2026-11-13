import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../fees/domain/money.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_fee.dart';
import '../providers/admission_providers.dart';
import '../widgets/fees_tab.dart';

/// Finance's list of admission fees still to collect. It shows the enquiry
/// NUMBER, the fee and the money: nothing about the applicant or the enquiry.
/// Payments are recorded through the same server step as everywhere else.
class AdmissionFeesPage extends ConsumerWidget {
  const AdmissionFeesPage({super.key});

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    AdmissionFee f,
    String schoolId,
    String branchId,
  ) async {
    final r = await showDialog<AdmissionPaymentInput>(
      context: context,
      builder: (_) => AdmissionPaymentDialog(fee: f),
    );
    if (r == null || !context.mounted) return;
    final receipt = await ref
        .read(admissionWriteControllerProvider.notifier)
        .recordPayment(
          key: (schoolId: schoolId, branchId: branchId, enquiryId: f.enquiryId),
          category: f.category,
          requestId: r.requestId,
          amountMinor: r.amountMinor,
          method: r.method,
          referenceNo: r.referenceNo,
          notes: r.notes,
        );
    ref.invalidate(
      openAdmissionFeesProvider((schoolId: schoolId, branchId: branchId)),
    );
    if (!context.mounted) return;
    if (receipt != null) {
      context.showSnackBar('Payment recorded. Receipt $receipt.');
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.payments_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final fees = ref.watch(
          openAdmissionFeesProvider((schoolId: schoolId, branchId: branchId)),
        );
        final busy = ref.watch(admissionWriteControllerProvider).isLoading;
        final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        return ListView(
          padding: EdgeInsets.all(layout.isMobile ? 16 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: fees.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => ParentsCard(child: Text(userMessageFor(e))),
                  data: (list) {
                    if (list.isEmpty) {
                      return const EmptyView(
                        icon: Icons.task_alt_outlined,
                        message:
                            'No admission fees are waiting to be collected.',
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final f in list) ...[
                          ParentsCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${f.enquiryNumber ?? 'Enquiry'} · ${f.category.label}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                    ),
                                    ParentsBadge(
                                      f.status.label,
                                      tone:
                                          f.status == AdmissionFeeStatus.partial
                                          ? ParentsTone.warning
                                          : ParentsTone.danger,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Asked ${Money.format(f.amountMinor, currency: f.currency)} · '
                                  'paid ${Money.format(f.netPaidMinor, currency: f.currency)} · '
                                  'due ${Money.format(f.balanceMinor, currency: f.currency)}',
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () => _record(
                                            context,
                                            ref,
                                            f,
                                            schoolId,
                                            branchId,
                                          ),
                                    child: const Text('Record payment'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
