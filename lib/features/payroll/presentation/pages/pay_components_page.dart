import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../domain/payroll.dart';
import '../providers/payroll_providers.dart';

/// `/payroll/components`: the school's own earnings and deductions. No
/// statutory rule is built in; the school defines what it pays and deducts.
/// Everyone who may see payroll can read; only a school admin changes them.
class PayComponentsPage extends ConsumerWidget {
  const PayComponentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = ref.watch(tenantContextProvider).value?.user.schoolId;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay components')),
      body: schoolId == null
          ? const Center(child: CircularProgressIndicator())
          : _Components(schoolId: schoolId),
    );
  }
}

class _Components extends ConsumerWidget {
  final String schoolId;

  const _Components({required this.schoolId});

  void _refresh(WidgetRef ref) {
    ref.invalidate(payAllComponentsProvider(schoolId));
    ref.invalidate(payComponentsProvider(schoolId));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<PayComponent> all, [
    PayComponent? c,
  ]) async {
    final result = await showDialog<_ComponentForm>(
      context: context,
      builder: (_) => _ComponentDialog(current: c, all: all),
    );
    if (result == null) return;
    try {
      await ref
          .read(payrollRepositoryProvider)
          .saveComponent(
            schoolId,
            componentId: c?.id,
            name: result.name,
            kind: c == null ? result.kind : null,
            calc: c == null ? result.calc : null,
            basisComponentId: c == null ? result.basisId : null,
            percentBp: result.percentBp,
          );
      _refresh(ref);
    } catch (e) {
      if (context.mounted) _toast(context, e);
    }
  }

  void _toast(BuildContext context, Object e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    PayComponent c,
    bool active,
  ) async {
    try {
      await ref
          .read(payrollRepositoryProvider)
          .saveComponent(
            schoolId,
            componentId: c.id,
            name: c.name,
            active: active,
          );
      _refresh(ref);
    } catch (e) {
      if (context.mounted) _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(payAllComponentsProvider(schoolId));
    if (loaded.hasError) {
      return ErrorView(
        message: userMessageFor(loaded.error!),
        onRetry: () => ref.invalidate(payAllComponentsProvider(schoolId)),
      );
    }
    final data = loaded.value;
    if (data == null) return const Center(child: CircularProgressIndicator());
    final byId = {for (final c in data.components) c.id: c};
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (data.canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('component-add'),
              onPressed: () => _edit(context, ref, data.components),
              icon: const Icon(Icons.add),
              label: const Text('Add component'),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        for (final c in data.components)
          Card(
            child: ListTile(
              key: ValueKey('component-${c.id}'),
              title: Text(c.name),
              subtitle: Text(
                [
                  c.kind.label,
                  if (c.calc == PayCalc.percent)
                    '${percentText(c.percentBp ?? 0)} of ${byId[c.basisComponentId]?.name ?? 'another earning'}'
                  else
                    'Fixed amount per person',
                  if (c.system) 'Built in',
                  if (!c.active) 'Not in use',
                ].join(' · '),
              ),
              trailing: data.canManage
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              _edit(context, ref, data.components, c),
                        ),
                        if (!c.system)
                          Switch(
                            value: c.active,
                            onChanged: (v) => _toggle(context, ref, c, v),
                          ),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _ComponentForm {
  final String name;
  final PayKind kind;
  final PayCalc calc;
  final String? basisId;
  final int? percentBp;

  const _ComponentForm(
    this.name,
    this.kind,
    this.calc,
    this.basisId,
    this.percentBp,
  );
}

class _ComponentDialog extends StatefulWidget {
  final PayComponent? current;
  final List<PayComponent> all;

  const _ComponentDialog({required this.current, required this.all});

  @override
  State<_ComponentDialog> createState() => _ComponentDialogState();
}

class _ComponentDialogState extends State<_ComponentDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current?.name ?? '',
  );
  late final TextEditingController _percent = TextEditingController(
    text: widget.current?.percentBp == null
        ? ''
        : percentText(widget.current!.percentBp!).replaceAll('%', ''),
  );
  late PayKind _kind = widget.current?.kind ?? PayKind.earning;
  late PayCalc _calc = widget.current?.calc ?? PayCalc.fixed;
  late String? _basis = widget.current?.basisComponentId;
  String? _error;

  bool get _isNew => widget.current == null;

  List<PayComponent> get _bases => [
    for (final c in widget.all)
      if (c.active && c.kind == PayKind.earning && c.calc == PayCalc.fixed) c,
  ];

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  void _submit() {
    final nameError = PayComponent.validateName(
      _name.text,
      widget.all,
      exceptId: widget.current?.id,
    );
    if (nameError != null) return setState(() => _error = nameError);
    int? bp;
    if (_calc == PayCalc.percent) {
      bp = parsePercentBp(_percent.text);
      if (bp == null) {
        return setState(
          () => _error = 'Enter a percentage up to 100 (for example 12.5).',
        );
      }
      if (_isNew && _basis == null) {
        return setState(() => _error = 'Choose what the percentage is of.');
      }
    }
    Navigator.pop(
      context,
      _ComponentForm(_name.text.trim(), _kind, _calc, _basis, bp),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add component' : 'Edit component'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('component-name'),
              controller: _name,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              enabled: widget.current?.system != true,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PayKind>(
              value: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final k in PayKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: _isNew
                  ? (v) => setState(() => _kind = v ?? _kind)
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PayCalc>(
              value: _calc,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'How it is worked out',
              ),
              items: [
                for (final c in PayCalc.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: _isNew
                  ? (v) => setState(() => _calc = v ?? _calc)
                  : null,
            ),
            if (_calc == PayCalc.percent) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _basis,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Percentage of'),
                items: [
                  for (final b in _bases)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: _isNew ? (v) => setState(() => _basis = v) : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('component-percent'),
                controller: _percent,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default percentage',
                  suffixText: '%',
                ),
              ),
            ],
            if (!_isNew)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  'Type and calculation cannot change after a component is created; add a new one instead.',
                  style: Theme.of(context).textTheme.bodySmall,
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
          key: const ValueKey('component-save'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
