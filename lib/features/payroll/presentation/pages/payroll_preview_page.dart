import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/payroll.dart';
import '../../domain/payroll_preview.dart';
import '../providers/payroll_providers.dart';

/// `/payroll/preview`: what each staff member would be paid for a month, from
/// their salary structure, the branch calendar, attendance and approved
/// leave. Nothing is saved. Tap a person to see exactly how it was worked out.
class PayrollPreviewPage extends ConsumerWidget {
  const PayrollPreviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay for a month')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _Preview(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _Preview extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;

  const _Preview({super.key, required this.schoolId, required this.branchId});

  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  late final List<String> _periods;
  late String _period;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periods = recentPeriods(now.year, now.month);
    _period = _periods.first;
  }

  PreviewKey get _key =>
      (schoolId: widget.schoolId, branchId: widget.branchId, period: _period);

  Future<void> _settings() async {
    final loaded = await ref.read(
      payrollSettingsProvider(widget.schoolId).future,
    );
    if (!mounted) return;
    final chosen = await showDialog<({UnmarkedDays unmarked, bool self})>(
      context: context,
      builder: (_) => _SettingsDialog(
        current: loaded.settings,
        canManage: loaded.canManage,
      ),
    );
    if (chosen == null ||
        (chosen.unmarked == loaded.settings.unmarkedDays &&
            chosen.self == loaded.settings.allowSelfApproval)) {
      return;
    }
    try {
      await ref
          .read(payrollRepositoryProvider)
          .savePayrollSettings(
            widget.schoolId,
            chosen.unmarked,
            allowSelfApproval: chosen.self,
            baseVersion: loaded.settings.version,
          );
      ref.invalidate(payrollSettingsProvider(widget.schoolId));
      ref.invalidate(payPreviewProvider(_key));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(payPreviewProvider(_key));
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('preview-period'),
                  value: _period,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    for (final p in _periods)
                      DropdownMenuItem(value: p, child: Text(periodLabel(p))),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? _period),
                ),
              ),
              IconButton(
                key: const ValueKey('preview-settings'),
                tooltip: 'Days nobody marked',
                icon: const Icon(Icons.rule),
                onPressed: _settings,
              ),
            ],
          ),
        ),
        Expanded(
          child: loaded.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(payPreviewProvider(_key)),
            ),
            data: (data) {
              if (data.rows.isEmpty) {
                return const EmptyView(
                  icon: Icons.groups_outlined,
                  message: 'No staff to pay in this branch for that month.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(
                    '${periodLabel(data.period)}: ${data.workingDays} school days. '
                    'Days nobody marked: ${data.unmarkedDays == UnmarkedDays.paid ? 'paid' : 'not paid'}.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final r in data.rows)
                    Card(
                      child: ListTile(
                        key: ValueKey('preview-${r.staff.id}'),
                        title: Text(r.staff.name),
                        subtitle: Text(
                          r.hasStructure
                              ? 'Paid ${daysText(r.paidDays)} of ${r.workingDays} days'
                                    '${r.warningCount > 0 ? ' · ${r.warningCount} to check' : ''}'
                              : 'No salary structure',
                        ),
                        trailing: r.hasStructure
                            ? Text(
                                Money.format(
                                  r.netMinor,
                                  currency: data.currency,
                                ),
                                style: text.titleMedium,
                              )
                            : const Icon(Icons.warning_amber_outlined),
                        onTap: r.hasStructure
                            ? () => showDialog<void>(
                                context: context,
                                builder: (_) => _Explain(
                                  schoolId: widget.schoolId,
                                  branchId: widget.branchId,
                                  staffId: r.staff.id,
                                  period: data.period,
                                ),
                              )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  final PayrollSettings current;
  final bool canManage;

  const _SettingsDialog({required this.current, required this.canManage});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late UnmarkedDays _value = widget.current.unmarkedDays;
  late bool _self = widget.current.allowSelfApproval;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('A school day nobody marked'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final u in UnmarkedDays.values)
              RadioListTile<UnmarkedDays>(
                key: ValueKey('unmarked-${u.wire}'),
                value: u,
                groupValue: _value,
                onChanged: widget.canManage
                    ? (v) => setState(() => _value = v ?? _value)
                    : null,
                title: Text(u.label),
                contentPadding: EdgeInsets.zero,
              ),
            SwitchListTile(
              key: const ValueKey('allow-self-approval'),
              contentPadding: EdgeInsets.zero,
              value: _self,
              onChanged: widget.canManage
                  ? (v) => setState(() => _self = v)
                  : null,
              title: const Text('Let one administrator prepare and approve'),
              subtitle: const Text(
                'Off by default: the person who prepared a payroll run cannot approve it.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.canManage
                  ? 'Either way, every unmarked day is listed as something to check.'
                  : 'Only a school admin can change this.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (widget.canManage)
          FilledButton(
            key: const ValueKey('unmarked-save'),
            onPressed: () =>
                Navigator.pop(context, (unmarked: _value, self: _self)),
            child: const Text('Save'),
          ),
      ],
    );
  }
}

class _Explain extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String staffId;
  final String period;

  const _Explain({
    required this.schoolId,
    required this.branchId,
    required this.staffId,
    required this.period,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(
      payPreviewStaffProvider((
        schoolId: schoolId,
        branchId: branchId,
        staffId: staffId,
        period: period,
      )),
    );
    return AlertDialog(
      title: Text(loaded.value?.staff.name ?? 'Pay'),
      content: SizedBox(
        width: 420,
        child: loaded.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(userMessageFor(e)),
          data: (d) => _ExplainBody(d),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ExplainBody extends StatelessWidget {
  final PayPreviewStaff d;

  const _ExplainBody(this.d);

  @override
  Widget build(BuildContext context) {
    final c = d.calculation;
    final text = Theme.of(context).textTheme;
    if (c == null) return const Text('No salary structure for this month.');
    String money(int v) => Money.format(v, currency: d.currency);
    String n(String k) => daysText(c.days[k] ?? 0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(periodLabel(d.period), style: text.titleSmall),
          Text(
            'Paid ${daysText(c.paidDays)} of ${c.workingDays} school days',
            key: const ValueKey('explain-days'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              Chip(label: Text('Present ${n('present')}')),
              if ((c.days['late'] ?? 0) > 0)
                Chip(label: Text('Late ${n('late')}')),
              if ((c.days['halfDay'] ?? 0) > 0)
                Chip(label: Text('Half days ${n('halfDay')}')),
              if ((c.days['absent'] ?? 0) > 0)
                Chip(label: Text('Absent ${n('absent')}')),
              if ((c.days['paidLeave'] ?? 0) > 0)
                Chip(label: Text('Paid leave ${n('paidLeave')}')),
              if ((c.days['unpaidLeave'] ?? 0) > 0)
                Chip(label: Text('Unpaid leave ${n('unpaidLeave')}')),
              if ((c.days['unmarked'] ?? 0) > 0)
                Chip(label: Text('Not marked ${n('unmarked')}')),
              if ((c.days['notEmployed'] ?? 0) > 0)
                Chip(label: Text('Not employed ${n('notEmployed')}')),
            ],
          ),
          const Divider(),
          for (final l in c.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(l.name)),
                  if (l.reduced)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Text(
                        money(l.plannedMinor),
                        style: text.bodySmall?.copyWith(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  Text(
                    '${l.kind == PayKind.deduction ? '- ' : ''}${money(l.amountMinor)}',
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Net pay')),
              Text(
                money(c.netMinor),
                key: const ValueKey('explain-net'),
                style: text.titleMedium,
              ),
            ],
          ),
          if (c.unrecoveredDeductionMinor > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${money(c.unrecoveredDeductionMinor)} of deductions could not be taken from this month\'s pay.',
                style: text.bodySmall,
              ),
            ),
          if (c.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('To check', style: text.titleSmall),
            for (final w in c.warnings.take(8)) Text('• ${w.text}'),
            if (c.warnings.length > 8)
              Text('and ${c.warnings.length - 8} more'),
          ],
        ],
      ),
    );
  }
}
