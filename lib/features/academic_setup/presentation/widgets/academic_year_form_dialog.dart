import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/academic_year.dart';
import '../../domain/academic_year_status.dart';
import '../providers/academic_structure_providers.dart';

class AcademicYearFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String currentUserId;
  final AcademicYear? existing;

  const AcademicYearFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.currentUserId,
    this.existing,
  });

  @override
  ConsumerState<AcademicYearFormDialog> createState() =>
      _AcademicYearFormDialogState();
}

class _AcademicYearFormDialogState
    extends ConsumerState<AcademicYearFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late DateTime? _startDate = widget.existing?.startDate;
  late DateTime? _endDate = widget.existing?.endDate;
  late AcademicYearStatus _status =
      widget.existing?.status ?? AcademicYearStatus.draft;

  bool get _isEditing => widget.existing != null;

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate == null || _endDate == null) {
      context.showSnackBar(
        'Please choose both a start and end date.',
        isError: true,
      );
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      context.showSnackBar(
        'End date must be after the start date.',
        isError: true,
      );
      return;
    }

    final year = AcademicYear(
      academicYearId: widget.existing?.academicYearId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      name: _name.text.trim(),
      startDate: _startDate!,
      endDate: _endDate!,
      status: _status,
    );

    final repository = ref.read(academicStructureRepositoryProvider);
    final success = await ref
        .read(academicStructureWriteControllerProvider.notifier)
        .run(
          () => _isEditing
              ? repository.updateAcademicYear(
                  year,
                  updatedBy: widget.currentUserId,
                )
              : repository
                    .createAcademicYear(year, createdBy: widget.currentUserId)
                    .then((_) {}),
        );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(academicStructureWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save the academic year.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref
        .watch(academicStructureWriteControllerProvider)
        .isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? 'Edit academic year' : 'Add academic year',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. 2026-2027',
            ),
            validator: (v) => Validators.required(v, fieldName: 'Name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: Text(
                    _startDate == null
                        ? 'Start date'
                        : formatDisplayDate(_startDate!),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isStart: false),
                  child: Text(
                    _endDate == null
                        ? 'End date'
                        : formatDisplayDate(_endDate!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<AcademicYearStatus>(
            isExpanded: true,
            value: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in AcademicYearStatus.values)
                DropdownMenuItem(value: s, child: Text(s.displayName)),
            ],
            onChanged: (value) => setState(() => _status = value ?? _status),
          ),
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
