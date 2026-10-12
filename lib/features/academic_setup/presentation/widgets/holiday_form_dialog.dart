import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/holiday.dart';
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
  late HolidayType _type = widget.existing?.type ?? HolidayType.school;
  late ActivationStatus _status =
      widget.existing?.status ?? ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final holiday = Holiday(
      holidayId: widget.existing?.holidayId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.academicYearId,
      date: _date,
      name: _name.text.trim(),
      type: _type,
      description: _description.text.trim(),
      status: _status,
    );

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
          OutlinedButton(
            onPressed: _pickDate,
            child: Text(formatDisplayDate(_date)),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Holiday name'),
            validator: (v) => Validators.required(v, fieldName: 'Holiday name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<HolidayType>(
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
