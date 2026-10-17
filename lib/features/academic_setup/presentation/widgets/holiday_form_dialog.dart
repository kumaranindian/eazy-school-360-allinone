import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/holiday.dart';
import '../../domain/holiday_rules.dart';
import '../../domain/holiday_type.dart';
import '../providers/calendar_providers.dart';

class HolidayFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String currentUserId;
  final Holiday? existing;
  final DateTime? initialDate;

  const HolidayFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.currentUserId,
    this.existing,
    this.initialDate,
  });

  @override
  ConsumerState<HolidayFormDialog> createState() => _HolidayFormDialogState();
}

class _HolidayFormDialogState extends ConsumerState<HolidayFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late DateTime _date =
      widget.existing?.date ?? widget.initialDate ?? DateTime.now();
  // A multi-day holiday or vacation has a last day; a single day does not.
  late bool _multiDay = widget.existing?.isRange ?? false;
  late DateTime _endDate = widget.existing?.endDate ?? _date;
  late HolidayType _type = widget.existing?.type ?? HolidayType.school;
  late ActivationStatus _status =
      widget.existing?.status ?? ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _pickDate({required bool end}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? _endDate : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: end ? 'Last day' : 'First day',
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endDate = picked;
      } else {
        _date = picked;
        if (!_multiDay || _endDate.isBefore(picked)) _endDate = picked;
      }
    });
  }

  Future<bool> _confirmOverlap(List<Holiday> overlapping) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This overlaps other holidays'),
        content: Text(
          'These days are already covered by:\n'
          '${overlapping.map((h) => '• ${h.name} (${formatDisplayDate(h.date)}'
              '${h.isRange ? ' – ${formatDisplayDate(h.lastDate)}' : ''})').join('\n')}'
          '\n\nBoth are kept. The calendar shows the more specific label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final end = _multiDay ? _endDate : null;
    final rangeError = HolidayRules.checkRange(_date, end);
    if (rangeError != null) {
      context.showSnackBar(rangeError, isError: true);
      return;
    }

    final holiday = Holiday(
      holidayId: widget.existing?.holidayId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.academicYearId,
      date: _date,
      endDate: end,
      name: _name.text.trim(),
      type: _type,
      description: _description.text.trim(),
      status: _status,
    );

    // Overlap is allowed but never silent; a repeat of the same name on the
    // same day is refused by the repository.
    final existingList =
        ref
            .read(
              holidaysProvider((
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                academicYearId: widget.academicYearId,
              )),
            )
            .value ??
        const <Holiday>[];
    final overlapping = _status == ActivationStatus.active
        ? HolidayRules.overlapping(holiday, existingList)
        : const <Holiday>[];
    if (overlapping.isNotEmpty && !await _confirmOverlap(overlapping)) return;
    if (!mounted) return;

    final repository = ref.read(calendarRepositoryProvider);
    final success = await ref
        .read(calendarWriteControllerProvider.notifier)
        .run(
          () => _isEditing
              ? repository.updateHoliday(
                  holiday,
                  updatedBy: widget.currentUserId,
                )
              : repository
                    .createHoliday(holiday, createdBy: widget.currentUserId)
                    .then((_) {}),
        );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(calendarWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save the holiday.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(calendarWriteControllerProvider).isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? 'Edit holiday' : 'Add holiday',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            key: const ValueKey('firstDay'),
            onPressed: () => _pickDate(end: false),
            icon: const Icon(Icons.event),
            label: Text(
              '${_multiDay ? 'First day: ' : ''}${formatDisplayDate(_date)}',
            ),
          ),
          SwitchListTile(
            key: const ValueKey('multiDay'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Spans several days (vacation)'),
            value: _multiDay,
            onChanged: (v) => setState(() {
              _multiDay = v;
              if (!v) _endDate = _date;
            }),
          ),
          if (_multiDay)
            OutlinedButton.icon(
              key: const ValueKey('lastDay'),
              onPressed: () => _pickDate(end: true),
              icon: const Icon(Icons.event_available),
              label: Text('Last day: ${formatDisplayDate(_endDate)}'),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Holiday name'),
            validator: (v) => Validators.required(v, fieldName: 'Holiday name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<HolidayType>(
            isExpanded: true,
            value: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in HolidayType.values)
                DropdownMenuItem(value: t, child: Text(t.displayName)),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 2,
          ),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ActivationStatus>(
              isExpanded: true,
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(
                  value: ActivationStatus.active,
                  child: Text('Active'),
                ),
                DropdownMenuItem(
                  value: ActivationStatus.inactive,
                  child: Text('Inactive'),
                ),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: isSaving ? null : _submit,
                child: isSaving
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
