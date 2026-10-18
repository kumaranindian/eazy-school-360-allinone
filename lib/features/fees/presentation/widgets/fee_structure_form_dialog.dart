import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_structure.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import 'fee_scope.dart';

/// Create or edit a fee structure. The code (with the academic year) is the
/// document id, so it is chosen once. Changes apply to invoices generated
/// from now on; issued invoices keep their own snapshot — the dialog says so.
class FeeStructureFormDialog extends ConsumerStatefulWidget {
  final FeeContext fee;
  final FeeStructure? existing;

  const FeeStructureFormDialog({super.key, required this.fee, this.existing});

  @override
  ConsumerState<FeeStructureFormDialog> createState() =>
      _FeeStructureFormDialogState();
}

class _FeeStructureFormDialogState
    extends ConsumerState<FeeStructureFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : Money.plain(
            widget.existing!.amountMinor,
            currency: widget.fee.currency,
          ),
  );
  late final _customCategory = TextEditingController(
    text: widget.existing?.customCategoryLabel,
  );
  late final _dueDays = TextEditingController(
    text: '${widget.existing?.dueOffsetDays ?? 15}',
  );
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _instructions = TextEditingController(
    text: widget.existing?.paymentInstructions,
  );
  late FeeCategory _category = widget.existing?.category ?? FeeCategory.tuition;
  late FeeFrequency _frequency =
      widget.existing?.frequency ?? FeeFrequency.monthly;
  late String? _classId = widget.existing?.classId;
  late String? _sectionId = widget.existing?.sectionId;
  late bool _optional = widget.existing?.isOptional ?? false;
  late bool _active = widget.existing?.isActive ?? true;
  late String? _from = widget.existing?.effectiveFromKey;
  late String? _to = widget.existing?.effectiveToKey;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(
        () => from
            ? _from = FeeDates.todayKey(picked)
            : _to = FeeDates.todayKey(picked),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final fee = widget.fee;
    final structure = FeeStructure(
      structureId:
          widget.existing?.structureId ??
          FeeStructure.idFor(fee.year.academicYearId, _code.text),
      schoolId: fee.schoolId,
      branchId: fee.branchId,
      academicYearId: fee.year.academicYearId,
      code: widget.existing?.code ?? _code.text.trim(),
      name: _name.text.trim(),
      category: _category,
      customCategoryLabel: _customCategory.text.trim().isEmpty
          ? null
          : _customCategory.text.trim(),
      frequency: _frequency,
      amountMinor: Money.parseMinor(_amount.text, currency: fee.currency)!,
      classId: _classId,
      sectionId: _classId == null ? null : _sectionId,
      isOptional: _optional,
      effectiveFromKey: _from,
      effectiveToKey: _to,
      dueOffsetDays: int.tryParse(_dueDays.text.trim()) ?? 15,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      paymentInstructions: _instructions.text.trim().isEmpty
          ? null
          : _instructions.text.trim(),
      status: _active ? ActivationStatus.active : ActivationStatus.inactive,
    );
    setState(() => _busy = true);
    try {
      final repo = ref.read(feeConfigRepositoryProvider);
      _editing
          ? await repo.updateStructure(structure, actorId: fee.userId)
          : await repo.createStructure(structure, actorId: fee.userId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        context.showSnackBar(userMessageFor(error), isError: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _amount,
      _customCategory,
      _dueDays,
      _description,
      _instructions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final classes = (ref.watch(classesProvider(fee.yearKey)).value ?? const [])
        .where((c) => c.status.wireValue == 'ACTIVE')
        .toList();
    final sections = _classId == null
        ? const []
        : (ref
                      .watch(
                        sectionsProvider((
                          schoolId: fee.schoolId,
                          branchId: fee.branchId,
                          academicYearId: fee.year.academicYearId,
                          classId: _classId!,
                        )),
                      )
                      .value ??
                  const [])
              .where((s) => s.status.wireValue == 'ACTIVE')
              .toList();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing ? 'Edit fee' : 'Add fee',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Applies to invoices generated from now on. Invoices already issued keep the amounts they were billed with.',
            style: context.textStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _code,
            enabled: !_editing && !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Code',
              helperText: _editing
                  ? 'The code cannot be changed.'
                  : 'e.g. TUITION-5 — unique for the academic year',
            ),
            validator: (v) =>
                FeeStructure.codePattern.hasMatch((v ?? '').trim())
                ? null
                : '2-20 letters, digits, "-" or "_".',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Fee name'),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Enter a fee name.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<FeeCategory>(
            isExpanded: true,
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in FeeCategory.values)
                DropdownMenuItem(value: c, child: Text(c.displayName)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _category = v ?? _category),
          ),
          if (_category == FeeCategory.other) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _customCategory,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Category name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Name the category.' : null,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<FeeFrequency>(
            isExpanded: true,
            value: _frequency,
            decoration: const InputDecoration(labelText: 'Billed'),
            items: [
              for (final f in FeeFrequency.values)
                DropdownMenuItem(value: f, child: Text(f.displayName)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _frequency = v ?? _frequency),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (${fee.currency})',
              helperText: 'Per billing period.',
            ),
            validator: (v) {
              final minor = Money.parseMinor(v ?? '', currency: fee.currency);
              if (minor == null) {
                return Money.invalidAmountMessage(fee.currency);
              }
              if (minor <= 0) return 'The amount must be greater than zero.';
              if (minor > FeeStructure.maxAmountMinor) {
                return 'The amount is too large.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            value: classes.any((c) => c.classId == _classId) ? _classId : null,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All classes')),
              for (final c in classes)
                DropdownMenuItem(value: c.classId, child: Text(c.name)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _classId = v;
                    _sectionId = null;
                  }),
          ),
          if (_classId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              value: sections.any((s) => s.sectionId == _sectionId)
                  ? _sectionId
                  : null,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All sections'),
                ),
                for (final s in sections)
                  DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _sectionId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _pickDate(true),
                child: Text(
                  _from == null
                      ? 'Effective from: any'
                      : 'From ${FeeDates.display(_from!)}',
                ),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _pickDate(false),
                child: Text(
                  _to == null
                      ? 'Effective to: any'
                      : 'To ${FeeDates.display(_to!)}',
                ),
              ),
              if (_from != null || _to != null)
                TextButton(
                  onPressed: () => setState(() => _from = _to = null),
                  child: const Text('Clear dates'),
                ),
            ],
          ),
          if (_from != null && _to != null && _from!.compareTo(_to!) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The start date is after the end date.',
                style: TextStyle(color: context.colors.error),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _dueDays,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days until due after issue',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 0 || n > 365
                  ? 'Enter a number from 0 to 365.'
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _description,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Description (shown on invoices)',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _instructions,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Payment instructions (optional)',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Optional fee'),
            subtitle: const Text(
              'Not assigned in bulk unless chosen (e.g. transport).',
            ),
            value: _optional,
            onChanged: _busy ? null : (v) => setState(() => _optional = v),
          ),
          if (_editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive fees are not billed.'),
              value: _active,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
