import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/payroll.dart';
import '../providers/payroll_providers.dart';

/// `/payroll/staff/:staffId`: one person's salary structure. The version in
/// force today, every earlier version, and (school admin only) a form that
/// saves a NEW version. Old versions are never edited, so a past payslip can
/// never change.
class SalaryStructurePage extends ConsumerWidget {
  final String staffId;

  const SalaryStructurePage({super.key, required this.staffId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salary structure')),
      body: StaffBranchScope(
        showBranchRow: false,
        builder: (context, tenant, schoolId, branchId) => _Body(
          key: ValueKey('$schoolId/$branchId/$staffId'),
          schoolId: schoolId,
          branchId: branchId,
          staffId: staffId,
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String staffId;

  const _Body({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.staffId,
  });

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _editing = false;

  SalaryKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    staffId: widget.staffId,
  );

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(salaryStructureProvider(_key));
    final comps = ref.watch(payComponentsProvider(widget.schoolId));
    for (final a in [loaded, comps]) {
      if (a.hasError) {
        return ErrorView(
          message: userMessageFor(a.error!),
          onRetry: () {
            ref.invalidate(salaryStructureProvider(_key));
            ref.invalidate(payComponentsProvider(widget.schoolId));
          },
        );
      }
    }
    final view = loaded.value;
    final components = comps.value;
    if (view == null || components == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(view.staff.name, style: text.titleLarge),
        if (view.staff.employeeCode.isNotEmpty)
          Text(view.staff.employeeCode, style: text.bodySmall),
        const SizedBox(height: AppSpacing.md),
        if (_editing)
          _StructureForm(
            key: const ValueKey('structure-form'),
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            view: view,
            components: components.components,
            onDone: (saved) {
              setState(() => _editing = false);
              if (saved) {
                ref.invalidate(salaryStructureProvider(_key));
                ref.invalidate(
                  staffPayProvider((
                    schoolId: widget.schoolId,
                    branchId: widget.branchId,
                  )),
                );
              }
            },
          )
        else ...[
          if (view.current == null)
            const Text('No salary structure is in force yet.')
          else
            _StructureCard(
              title: 'In force now',
              s: view.current!,
              currency: view.currency,
            ),
          if (view.canEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('structure-edit'),
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    view.history.isEmpty ? 'Set salary' : 'Revise salary',
                  ),
                ),
              ),
            ),
        ],
        if (view.history.length > 1 ||
            (view.history.isNotEmpty && view.current == null)) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('History', style: text.titleMedium),
          for (final h in view.history)
            _StructureCard(
              title: 'Version ${h.seq} · from ${h.effectiveFrom}',
              s: h,
              currency: view.currency,
              compact: true,
            ),
        ],
      ],
    );
  }
}

class _StructureCard extends StatelessWidget {
  final String title;
  final SalaryStructure s;
  final String currency;
  final bool compact;

  const _StructureCard({
    required this.title,
    required this.s,
    required this.currency,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String money(int v) => Money.format(v, currency: currency);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            if (!compact)
              Text('Effective from ${s.effectiveFrom}', style: text.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            for (final l in s.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.calc == PayCalc.percent
                            ? '${l.name} (${percentText(l.percentBp ?? 0)})'
                            : l.name,
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
                Text(money(s.netMinor), style: text.titleMedium),
              ],
            ),
            if (s.reason != null && s.reason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Reason: ${s.reason}', style: text.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _StructureForm extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final SalaryStructureView view;
  final List<PayComponent> components;
  final void Function(bool saved) onDone;

  const _StructureForm({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.view,
    required this.components,
    required this.onDone,
  });

  @override
  ConsumerState<_StructureForm> createState() => _StructureFormState();
}

class _StructureFormState extends ConsumerState<_StructureForm> {
  final Map<String, TextEditingController> _amounts = {};
  final Set<String> _on = {};
  final TextEditingController _reason = TextEditingController();
  late String _from;
  bool _saving = false;
  String? _error;

  bool get _revision => widget.view.history.isNotEmpty;
  Map<String, PayComponent> get _byId => {
    for (final c in widget.components) c.id: c,
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final latest = widget.view.history.isEmpty
        ? null
        : widget.view.history.first;
    _from = firstOfMonth(now.year, now.month);
    if (latest != null && latest.effectiveFrom.compareTo(_from) > 0) {
      _from = latest.effectiveFrom;
    }
    for (final c in widget.components) {
      _amounts[c.id] = TextEditingController();
    }
    final seed = widget.view.current ?? latest;
    if (seed != null) {
      for (final l in seed.lines) {
        final c = _byId[l.componentId];
        if (c == null) continue;
        _on.add(c.id);
        if (c.calc == PayCalc.fixed) {
          _amounts[c.id]!.text = _majorText(l.amountMinor);
        } else if (l.percentBp != null) {
          _amounts[c.id]!.text = percentText(l.percentBp!).replaceAll('%', '');
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  /// Minor units as what a person types (no symbol, no grouping).
  String _majorText(int minor) => Money.format(
    minor,
    currency: widget.view.currency,
  ).replaceAll(RegExp(r'[^0-9.]'), '');

  List<SalaryLineInput> _inputs() {
    final out = <SalaryLineInput>[];
    for (final c in widget.components) {
      if (!_on.contains(c.id)) continue;
      final raw = _amounts[c.id]!.text;
      if (c.calc == PayCalc.fixed) {
        out.add(
          SalaryLineInput(
            componentId: c.id,
            amountMinor: Money.parseMinor(raw, currency: widget.view.currency),
          ),
        );
      } else {
        out.add(
          SalaryLineInput(
            componentId: c.id,
            percentBp: raw.trim().isEmpty ? c.percentBp : parsePercentBp(raw),
          ),
        );
      }
    }
    return out;
  }

  Future<void> _save() async {
    final preview = PayrollPreview.compute(_inputs(), _byId);
    if (!preview.valid) return setState(() => _error = preview.problem);
    if (_revision && _reason.text.trim().length < 10) {
      return setState(
        () => _error = 'Explain the change (at least 10 characters).',
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(payrollRepositoryProvider)
          .saveStructure(
            widget.schoolId,
            widget.branchId,
            widget.view.staff.id,
            effectiveFrom: _from,
            lines: _inputs(),
            reason: _revision ? _reason.text.trim() : null,
            baseSeq: widget.view.history.isEmpty
                ? 0
                : widget.view.history.first.seq,
          );
      if (mounted) widget.onDone(true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickMonth() async {
    final d = DateTime.parse(_from);
    final picked = await showDatePicker(
      context: context,
      initialDate: d,
      firstDate: DateTime(d.year - 2),
      lastDate: DateTime(d.year + 2, 12, 31),
      helpText: 'Effective from (the 1st of that month is used)',
    );
    if (picked != null) {
      setState(() => _from = firstOfMonth(picked.year, picked.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.view.currency;
    final preview = PayrollPreview.compute(_inputs(), _byId);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Effective from $_from')),
            TextButton(
              key: const ValueKey('structure-month'),
              onPressed: _pickMonth,
              child: const Text('Change'),
            ),
          ],
        ),
        for (final c in widget.components)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    key: ValueKey('use-${c.id}'),
                    contentPadding: EdgeInsets.zero,
                    value: _on.contains(c.id),
                    title: Text('${c.name} (${c.kind.label.toLowerCase()})'),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _on.add(c.id);
                      } else {
                        _on.remove(c.id);
                      }
                    }),
                  ),
                  if (_on.contains(c.id))
                    TextField(
                      key: ValueKey('value-${c.id}'),
                      controller: _amounts[c.id],
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: c.calc == PayCalc.fixed
                            ? 'Amount per month'
                            : 'Percentage (blank = default ${percentText(c.percentBp ?? 0)})',
                        suffixText: c.calc == PayCalc.percent ? '%' : null,
                        helperText:
                            c.calc == PayCalc.percent &&
                                preview.amounts[c.id] != null
                            ? Money.format(
                                preview.amounts[c.id]!,
                                currency: currency,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_revision)
          TextField(
            key: const ValueKey('structure-reason'),
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason for the change',
              helperText: 'Kept with the new version.',
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          preview.valid || preview.grossMinor > 0
              ? 'Gross ${Money.format(preview.grossMinor, currency: currency)} · '
                    'deductions ${Money.format(preview.deductionsMinor, currency: currency)} · '
                    'net ${Money.format(preview.netMinor, currency: currency)}'
              : 'Choose the components and enter the amounts.',
          key: const ValueKey('structure-preview'),
          style: text.titleSmall,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _error!,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const ValueKey('structure-save'),
              onPressed: _saving ? null : _save,
              child: const Text('Save new version'),
            ),
            TextButton(
              onPressed: _saving ? null : () => widget.onDone(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
