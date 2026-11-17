import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/payroll_preview.dart';
import '../../domain/payroll_run.dart';
import '../providers/payroll_providers.dart';

/// `/payroll/runs`: the branch's payroll runs, newest first, and a button to
/// start the month's run (one per branch and month). School admin and finance.
class PayrollRunsPage extends ConsumerWidget {
  const PayrollRunsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll runs')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _Runs(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _Runs extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;

  const _Runs({super.key, required this.schoolId, required this.branchId});

  @override
  ConsumerState<_Runs> createState() => _RunsState();
}

class _RunsState extends ConsumerState<_Runs> {
  bool _creating = false;

  PayBranchKey get _key =>
      (schoolId: widget.schoolId, branchId: widget.branchId);

  Future<void> _create(PayrollRunList list) async {
    final now = DateTime.now();
    final taken = {
      for (final r in list.runs)
        if (r.status != RunStatus.cancelled) r.period,
    };
    final free = [
      for (final p in recentPeriods(now.year, now.month))
        if (!taken.contains(p)) p,
    ];
    if (free.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every recent month already has a run.')),
      );
      return;
    }
    final period = await showDialog<String>(
      context: context,
      builder: (_) => _NewRunDialog(periods: free),
    );
    if (period == null) return;
    setState(() => _creating = true);
    try {
      await ref
          .read(payrollRepositoryProvider)
          .createRun(widget.schoolId, widget.branchId, period);
      ref.invalidate(payrollRunsProvider(_key));
      if (mounted) context.go('/payroll/runs/$period');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(payrollRunsProvider(_key));
    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(payrollRunsProvider(_key)),
      ),
      data: (list) {
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (list.canPrepare)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('run-new'),
                  onPressed: _creating ? null : () => _create(list),
                  icon: const Icon(Icons.add),
                  label: const Text('Start a month'),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (list.runs.isEmpty)
              const SizedBox(
                height: 240,
                child: EmptyView(
                  icon: Icons.payments_outlined,
                  message: 'No payroll runs yet.',
                ),
              ),
            for (final r in list.runs)
              Card(
                child: ListTile(
                  key: ValueKey('run-${r.period}'),
                  title: Text(periodLabel(r.period)),
                  subtitle: Text(
                    '${r.status.label} · ${r.payslipCount} payslips'
                    '${r.needsReview && r.status == RunStatus.calculated ? ' · to check' : ''}',
                  ),
                  trailing: r.status == RunStatus.cancelled
                      ? null
                      : Text(
                          Money.format(r.netMinor, currency: r.currency),
                          style: text.titleMedium,
                        ),
                  onTap: () => context.go('/payroll/runs/${r.period}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NewRunDialog extends StatefulWidget {
  final List<String> periods;

  const _NewRunDialog({required this.periods});

  @override
  State<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends State<_NewRunDialog> {
  late String _period = widget.periods.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start a month'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('run-period'),
            value: _period,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Month'),
            items: [
              for (final p in widget.periods)
                DropdownMenuItem(value: p, child: Text(periodLabel(p))),
            ],
            onChanged: (v) => setState(() => _period = v ?? _period),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Every payslip is worked out from salary structures, attendance and approved leave. You can review and adjust before it is approved.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('run-create'),
          onPressed: () => Navigator.pop(context, _period),
          child: const Text('Calculate'),
        ),
      ],
    );
  }
}
