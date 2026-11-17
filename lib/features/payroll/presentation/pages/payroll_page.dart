import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../providers/payroll_providers.dart';

/// `/payroll`: the branch's staff with the totals of their latest salary
/// structure (never the lines). School admin and finance only; the server
/// refuses anyone else.
class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: [
          IconButton(
            key: const ValueKey('payroll-runs'),
            tooltip: 'Payroll runs',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.go('/payroll/runs'),
          ),
          IconButton(
            key: const ValueKey('payroll-preview'),
            tooltip: 'Pay for a month',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => context.go('/payroll/preview'),
          ),
          IconButton(
            key: const ValueKey('payroll-components'),
            tooltip: 'Pay components',
            icon: const Icon(Icons.tune),
            onPressed: () => context.go('/payroll/components'),
          ),
        ],
      ),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _StaffPayList(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _StaffPayList extends ConsumerWidget {
  final String schoolId;
  final String branchId;

  const _StaffPayList({
    super.key,
    required this.schoolId,
    required this.branchId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (schoolId: schoolId, branchId: branchId);
    final loaded = ref.watch(staffPayProvider(key));
    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(staffPayProvider(key)),
      ),
      data: (data) {
        if (data.staff.isEmpty) {
          return const EmptyView(
            icon: Icons.groups_outlined,
            message: 'No staff in this branch yet.',
          );
        }
        final missing = data.staff.where((s) => !s.hasStructure).length;
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                missing == 0
                    ? 'Every staff member has a salary structure.'
                    : '$missing of ${data.staff.length} staff have no salary structure yet.',
                style: text.bodyMedium,
              ),
            ),
            for (final s in data.staff)
              Card(
                child: ListTile(
                  key: ValueKey('pay-${s.staff.id}'),
                  title: Text(s.staff.name),
                  subtitle: Text(
                    s.hasStructure
                        ? 'From ${s.effectiveFrom} · gross ${Money.format(s.grossMinor ?? 0, currency: data.currency)}'
                        : 'No salary structure',
                  ),
                  trailing: s.hasStructure
                      ? Text(
                          Money.format(
                            s.netMinor ?? 0,
                            currency: data.currency,
                          ),
                          style: text.titleMedium,
                        )
                      : const Icon(Icons.warning_amber_outlined),
                  onTap: () => context.go('/payroll/staff/${s.staff.id}'),
                ),
              ),
          ],
        );
      },
    );
  }
}
