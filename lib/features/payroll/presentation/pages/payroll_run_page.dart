import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../expenses/domain/expense.dart' show PaymentMode;
import '../../../expenses/presentation/pages/expense_reports_page.dart'
    show expenseCsvSaverProvider;
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/payroll.dart';
import '../../domain/payroll_preview.dart';
import '../../domain/payroll_repository.dart';
import '../../domain/payroll_run.dart';
import '../providers/payroll_providers.dart';
import '../../domain/payslip_document.dart';
import '../widgets/payslip_print.dart';

/// `/payroll/runs/:period`: one run. Its totals, what to check, every payslip,
/// and the actions the person may take (recalculate, adjust, approve, pay,
/// cancel). The server decides; the buttons only mirror its rules.
class PayrollRunPage extends ConsumerWidget {
  final String period;

  const PayrollRunPage({super.key, required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(periodLabel(period))),
      body: StaffBranchScope(
        showBranchRow: false,
        builder: (context, tenant, schoolId, branchId) => _Run(
          key: ValueKey('$schoolId/$branchId/$period'),
          schoolId: schoolId,
          branchId: branchId,
          period: period,
        ),
      ),
    );
  }
}

class _Run extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String period;

  const _Run({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.period,
  });

  @override
  ConsumerState<_Run> createState() => _RunState();
}

class _RunState extends ConsumerState<_Run> {
  bool _busy = false;

  RunKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    period: widget.period,
  );

  void _refresh() {
    ref.invalidate(payrollRunProvider(_key));
    ref.invalidate(payrollRunHistoryProvider(_key));
    ref.invalidate(
      payrollRunsProvider((
        schoolId: widget.schoolId,
        branchId: widget.branchId,
      )),
    );
  }

  Future<void> _do(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (mounted && done != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PayrollRepository get _repo => ref.read(payrollRepositoryProvider);

  Future<void> _exportCsv() async {
    await _do(() async {
      final out = await _repo.exportRegister(
        widget.schoolId,
        widget.branchId,
        widget.period,
      );
      final saved = await ref
          .read(expenseCsvSaverProvider)
          .save('payroll_register_${widget.period}.csv', out.csv);
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved ${out.rows} payslips.')));
      }
    });
  }

  Future<void> _approve(PayrollRunDetail d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ApproveDialog(run: d.run),
    );
    if (ok != true) return;
    await _do(
      () => _repo.approveRun(
        widget.schoolId,
        widget.branchId,
        widget.period,
        acknowledgeWarnings: d.run.needsReview,
        baseVersion: d.run.version,
      ),
      done: 'Run approved.',
    );
  }

  Future<void> _pay(PayrollRunDetail d) async {
    final p = await showDialog<_Payment>(
      context: context,
      builder: (_) => const _PayDialog(),
    );
    if (p == null) return;
    await _do(
      () => _repo.payRun(
        widget.schoolId,
        widget.branchId,
        widget.period,
        mode: p.mode,
        reference: p.reference.isEmpty ? null : p.reference,
        baseVersion: d.run.version,
      ),
      done: 'Run marked as paid.',
    );
  }

  Future<void> _cancel(PayrollRunDetail d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Cancel this run',
        label: 'Reason',
        action: 'Cancel run',
      ),
    );
    if (reason == null) return;
    await _do(
      () => _repo.cancelRun(
        widget.schoolId,
        widget.branchId,
        widget.period,
        reason: reason,
        baseVersion: d.run.version,
      ),
      done: 'Run cancelled.',
    );
  }

  Future<void> _openSlip(PayrollRunDetail d, PayslipRow row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SlipDialog(
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        period: widget.period,
        row: row,
        currency: d.run.currency,
        canAdjust: RunActions.canAdjust(d),
        run: d.run,
        baseVersion: d.run.version,
        onChanged: _refresh,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(payrollRunProvider(_key));
    if (loaded.hasError) {
      return ErrorView(
        message: userMessageFor(loaded.error!),
        onRetry: () => ref.invalidate(payrollRunProvider(_key)),
      );
    }
    final d = loaded.value;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final run = d.run;
    final text = Theme.of(context).textTheme;
    String money(int v) => Money.format(v, currency: run.currency);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      key: const ValueKey('run-status'),
                      label: Text(run.status.label),
                    ),
                    Text('${run.payslipCount} payslips'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Net pay ${money(run.netMinor)}',
                  key: const ValueKey('run-net'),
                  style: text.headlineSmall,
                ),
                Text(
                  'Earnings ${money(run.grossMinor)} · deductions ${money(run.deductionsMinor)}',
                  style: text.bodySmall,
                ),
                if (run.approvedByName != null)
                  Text(
                    'Approved by ${run.approvedByName}',
                    style: text.bodySmall,
                  ),
                if (run.status == RunStatus.paid)
                  Text(
                    'Paid ${run.paidDate ?? ''}${run.paymentMode == null ? '' : ' · ${PaymentMode.fromWire(run.paymentMode)?.label ?? run.paymentMode}'}'
                    '${(run.paymentReference ?? '').isEmpty ? '' : ' · ${run.paymentReference}'}',
                    style: text.bodySmall,
                  ),
                if (run.status == RunStatus.paid && run.expenseNumber != null)
                  Text(
                    'Recorded as expense ${run.expenseNumber} (Salaries)',
                    key: const ValueKey('run-expense'),
                    style: text.bodySmall,
                  ),
                if (run.status == RunStatus.cancelled)
                  Text(
                    'Cancelled: ${run.cancelReason ?? ''}',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        if (run.status == RunStatus.calculated && run.needsReview)
          Card(
            key: const ValueKey('run-review'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                [
                  if (run.warningCount > 0)
                    '${run.warningCount} things to check on the payslips (days nobody marked, leave that overlaps).',
                  if (run.skippedCount > 0)
                    '${run.skippedCount} staff have no salary structure and are not in this run.',
                ].join(' '),
              ),
            ),
          ),
        if (run.unrecoveredDeductionMinor > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              '${money(run.unrecoveredDeductionMinor)} of deductions could not be taken this month.',
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (RunActions.canApprove(d))
              FilledButton(
                key: const ValueKey('run-approve'),
                onPressed: _busy ? null : () => _approve(d),
                child: const Text('Approve'),
              ),
            if (RunActions.canPay(d))
              FilledButton(
                key: const ValueKey('run-pay'),
                onPressed: _busy ? null : () => _pay(d),
                child: const Text('Mark as paid'),
              ),
            if (RunActions.canRecalculate(d))
              OutlinedButton(
                key: const ValueKey('run-recalculate'),
                onPressed: _busy
                    ? null
                    : () => _do(
                        () => _repo.recalculateRun(
                          widget.schoolId,
                          widget.branchId,
                          widget.period,
                          baseVersion: run.version,
                        ),
                        done: 'Recalculated.',
                      ),
                child: const Text('Recalculate'),
              ),
            if (run.status == RunStatus.paid)
              OutlinedButton.icon(
                key: const ValueKey('run-csv'),
                onPressed: _busy ? null : _exportCsv,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download register (CSV)'),
              ),
            if (run.status == RunStatus.paid &&
                run.expenseId != null &&
                (ref
                        .watch(tenantContextProvider)
                        .value
                        ?.can(Permission.viewExpenses) ??
                    false))
              TextButton(
                key: const ValueKey('run-open-expense'),
                onPressed: () => context.go('/expenses/${run.expenseId}'),
                child: const Text('Open the expense'),
              ),
            if (RunActions.canCancel(d))
              TextButton(
                key: const ValueKey('run-cancel'),
                onPressed: _busy ? null : () => _cancel(d),
                child: const Text('Cancel run'),
              ),
          ],
        ),
        if (run.status == RunStatus.calculated &&
            d.canApprove &&
            !d.allowSelfApproval)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'The person who prepared a run cannot approve it.',
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text('Payslips', style: text.titleMedium),
        for (final p in d.payslips)
          Card(
            child: ListTile(
              key: ValueKey('slip-${p.staffId}'),
              title: Text(p.name),
              subtitle: Text(
                'Paid ${daysText(p.paidDays)} of ${p.workingDays} days'
                '${p.adjustmentCount > 0 ? ' · ${p.adjustmentCount} adjustment${p.adjustmentCount == 1 ? '' : 's'}' : ''}'
                '${p.warningCount > 0 ? ' · ${p.warningCount} to check' : ''}',
              ),
              trailing: Text(money(p.netMinor), style: text.titleMedium),
              onTap: () => _openSlip(d, p),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _History(runKey: _key),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  final RunKey runKey;

  const _History({required this.runKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(payrollRunHistoryProvider(runKey));
    final text = Theme.of(context).textTheme;
    return ExpansionTile(
      key: const ValueKey('run-history'),
      title: Text('History', style: text.titleMedium),
      children: [
        if (h.value == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: CircularProgressIndicator(),
          )
        else
          for (final e in h.value!)
            ListTile(
              dense: true,
              title: Text(e.label),
              subtitle: Text(
                [
                  if (e.actorName != null) e.actorName!,
                  if ((e.reason ?? '').isNotEmpty) e.reason!,
                ].join(' · '),
              ),
            ),
      ],
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  final PayrollRun run;

  const _ApproveDialog({required this.run});

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  bool _reviewed = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.run;
    return AlertDialog(
      title: const Text('Approve this run'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Net pay ${Money.format(r.netMinor, currency: r.currency)} for ${r.payslipCount} people. After approval nothing in the run can change.',
          ),
          if (r.needsReview)
            CheckboxListTile(
              key: const ValueKey('run-reviewed'),
              contentPadding: EdgeInsets.zero,
              value: _reviewed,
              onChanged: (v) => setState(() => _reviewed = v == true),
              title: const Text('I have reviewed the things to check'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('run-approve-confirm'),
          onPressed: r.needsReview && !_reviewed
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _Payment {
  final PaymentMode mode;
  final String reference;

  const _Payment(this.mode, this.reference);
}

class _PayDialog extends StatefulWidget {
  const _PayDialog();

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  PaymentMode _mode = PaymentMode.bankTransfer;
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mark as paid'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<PaymentMode>(
            key: const ValueKey('pay-mode'),
            value: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'How it was paid'),
            items: [
              for (final m in PaymentMode.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('pay-reference'),
            controller: _ref,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
              helperText: 'Batch or transaction reference.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pay-confirm'),
          onPressed: () =>
              Navigator.pop(context, _Payment(_mode, _ref.text.trim())),
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String label;
  final String action;

  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.action,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('reason-field'),
        controller: _c,
        maxLength: 300,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: 'At least 10 characters. It is kept with the run.',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const ValueKey('reason-confirm'),
          onPressed: () {
            if (_c.text.trim().length < 10) {
              setState(() => _error = 'Use at least 10 characters.');
              return;
            }
            Navigator.pop(context, _c.text.trim());
          },
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _SlipDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String period;
  final PayslipRow row;
  final String currency;
  final bool canAdjust;
  final PayrollRun run;
  final int baseVersion;
  final VoidCallback onChanged;

  const _SlipDialog({
    required this.schoolId,
    required this.branchId,
    required this.period,
    required this.row,
    required this.currency,
    required this.canAdjust,
    required this.run,
    required this.baseVersion,
    required this.onChanged,
  });

  @override
  ConsumerState<_SlipDialog> createState() => _SlipDialogState();
}

class _SlipDialogState extends ConsumerState<_SlipDialog> {
  PayslipKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    period: widget.period,
    staffId: widget.row.staffId,
  );

  Future<void> _add() async {
    final a = await showDialog<_AdjustmentForm>(
      context: context,
      builder: (_) => _AdjustmentDialog(currency: widget.currency),
    );
    if (a == null) return;
    await _run(
      () => ref
          .read(payrollRepositoryProvider)
          .addAdjustment(
            widget.schoolId,
            widget.branchId,
            widget.period,
            widget.row.staffId,
            kind: a.kind,
            label: a.label,
            amountMinor: a.amountMinor,
            reason: a.reason,
          ),
    );
  }

  Future<void> _remove(PayAdjustment a) => _run(
    () => ref
        .read(payrollRepositoryProvider)
        .removeAdjustment(
          widget.schoolId,
          widget.branchId,
          widget.period,
          widget.row.staffId,
          a.id,
        ),
  );

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(payslipProvider(_key));
      widget.onChanged();
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
    final loaded = ref.watch(payslipProvider(_key));
    final text = Theme.of(context).textTheme;
    String money(int v) => Money.format(v, currency: widget.currency);
    return AlertDialog(
      title: Text(widget.row.name),
      content: SizedBox(
        width: 440,
        child: loaded.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(userMessageFor(e)),
          data: (p) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Paid ${daysText(p.row.paidDays)} of ${p.row.workingDays} school days',
                ),
                const Divider(),
                for (final l in p.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(l.name)),
                        if (l.reduced)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.xs,
                            ),
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
                for (final a in p.adjustments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text('${a.label} (one-off)')),
                        Text(
                          '${a.kind == PayKind.deduction ? '- ' : ''}${money(a.amountMinor)}',
                        ),
                        if (widget.canAdjust)
                          IconButton(
                            key: ValueKey('adj-remove-${a.id}'),
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _remove(a),
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    const Expanded(child: Text('Net pay')),
                    Text(
                      money(p.row.netMinor),
                      key: const ValueKey('slip-net'),
                      style: text.titleMedium,
                    ),
                  ],
                ),
                if (p.unrecoveredDeductionMinor > 0)
                  Text(
                    '${money(p.unrecoveredDeductionMinor)} of deductions could not be taken.',
                    style: text.bodySmall,
                  ),
                if (p.warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('To check', style: text.titleSmall),
                  for (final w in p.warnings.take(8)) Text('• $w'),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        // The official payslip exists once the run is paid (published).
        if (widget.run.status == RunStatus.paid)
          TextButton(
            key: const ValueKey('slip-pdf'),
            onPressed: () async {
              final p = loaded.value;
              if (p == null) return;
              final doc = PayslipDocument.fromAdmin(
                p,
                widget.run,
                schoolName: '',
                branchName: '',
              );
              await PayslipPrint.download(
                ref,
                doc,
                schoolId: widget.schoolId,
                branchId: widget.branchId,
              );
            },
            child: const Text('Download PDF'),
          ),
        if (widget.canAdjust)
          TextButton(
            key: const ValueKey('adj-add'),
            onPressed: _add,
            child: const Text('Add one-off item'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AdjustmentForm {
  final PayKind kind;
  final String label;
  final int amountMinor;
  final String reason;

  const _AdjustmentForm(this.kind, this.label, this.amountMinor, this.reason);
}

class _AdjustmentDialog extends StatefulWidget {
  final String currency;

  const _AdjustmentDialog({required this.currency});

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  PayKind _kind = PayKind.earning;
  final _label = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim();
    final amount = Money.parseMinor(_amount.text, currency: widget.currency);
    if (label.length < 2 || label.length > 60) {
      return setState(() => _error = 'Name the item (2 to 60 characters).');
    }
    if (amount == null || amount < 1) {
      return setState(() => _error = 'Enter an amount above 0.');
    }
    if (_reason.text.trim().length < 10) {
      return setState(() => _error = 'Explain why (at least 10 characters).');
    }
    Navigator.pop(
      context,
      _AdjustmentForm(_kind, label, amount, _reason.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a one-off item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<PayKind>(
              key: const ValueKey('adj-kind'),
              value: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final k in PayKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('adj-label'),
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Name (for example Diwali bonus)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('adj-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('adj-reason'),
              controller: _reason,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('adj-save'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
