import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../domain/payroll_preview.dart';
import '../providers/payroll_providers.dart';

/// `/my-payslips`: the months the signed-in staff member has been paid. Only
/// their own; a payslip appears here when its payroll run is marked as paid.
class MyPayslipsPage extends ConsumerWidget {
  const MyPayslipsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = ref.watch(tenantContextProvider).value?.user.schoolId;
    return Scaffold(
      appBar: AppBar(title: const Text('My payslips')),
      body: schoolId == null
          ? const Center(child: CircularProgressIndicator())
          : _List(schoolId: schoolId),
    );
  }
}

class _List extends ConsumerWidget {
  final String schoolId;

  const _List({required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(myPayslipsProvider(schoolId));
    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(myPayslipsProvider(schoolId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const EmptyView(
            icon: Icons.request_page_outlined,
            message:
                'No payslips yet. They appear here once your school has paid the month.',
          );
        }
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            for (final r in rows)
              Card(
                child: ListTile(
                  key: ValueKey('mypay-${r.period}'),
                  title: Text(periodLabel(r.period)),
                  subtitle: r.paidDate == null
                      ? null
                      : Text('Paid ${r.paidDate}'),
                  trailing: Text(
                    Money.format(r.netMinor, currency: r.currency),
                    style: text.titleMedium,
                  ),
                  onTap: () =>
                      context.go('/my-payslips/${r.branchId}/${r.period}'),
                ),
              ),
          ],
        );
      },
    );
  }
}
