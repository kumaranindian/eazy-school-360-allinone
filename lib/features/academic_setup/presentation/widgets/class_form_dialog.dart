import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/school_class.dart';
import '../providers/academic_structure_providers.dart';

class ClassFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String currentUserId;
  final int nextDisplayOrder;
  final SchoolClass? existing;

  const ClassFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.currentUserId,
    required this.nextDisplayOrder,
    this.existing,
  });

  @override
  ConsumerState<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends ConsumerState<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _code = TextEditingController(text: widget.existing?.code);
  late ActivationStatus _status =
      widget.existing?.status ?? ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final schoolClass = SchoolClass(
      classId: widget.existing?.classId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.academicYearId,
      name: _name.text.trim(),
      code: _code.text.trim(),
      displayOrder: widget.existing?.displayOrder ?? widget.nextDisplayOrder,
      status: _status,
    );

    final repository = ref.read(academicStructureRepositoryProvider);
    final success = await ref
        .read(academicStructureWriteControllerProvider.notifier)
        .run(
          () => _isEditing
              ? repository.updateClass(
                  schoolClass,
                  updatedBy: widget.currentUserId,
                )
              : repository
                    .createClass(schoolClass, createdBy: widget.currentUserId)
                    .then((_) {}),
        );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(academicStructureWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save the class.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
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
            _isEditing ? 'Edit class' : 'Add class',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Class name',
              hintText: 'e.g. Class 5',
            ),
            validator: (v) => Validators.required(v, fieldName: 'Class name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Class code (optional)',
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ActivationStatus>(
              isExpanded: true,
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                DropdownMenuItem(
                  value: ActivationStatus.active,
                  child: const Text('Active'),
                ),
                DropdownMenuItem(
                  value: ActivationStatus.inactive,
                  child: const Text('Inactive'),
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
