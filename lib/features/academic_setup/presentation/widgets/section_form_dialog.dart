import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/section.dart';
import '../providers/academic_structure_providers.dart';

class SectionFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String currentUserId;
  final Section? existing;

  const SectionFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.currentUserId,
    this.existing,
  });

  @override
  ConsumerState<SectionFormDialog> createState() => _SectionFormDialogState();
}

class _SectionFormDialogState extends ConsumerState<SectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _capacity = TextEditingController(
    text: widget.existing?.capacity?.toString(),
  );
  late ActivationStatus _status =
      widget.existing?.status ?? ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final section = Section(
      sectionId: widget.existing?.sectionId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.academicYearId,
      classId: widget.classId,
      name: _name.text.trim(),
      code: _code.text.trim(),
      capacity: _capacity.text.trim().isEmpty
          ? null
          : int.tryParse(_capacity.text.trim()),
      status: _status,
    );

    final repository = ref.read(academicStructureRepositoryProvider);
    final success = await ref
        .read(academicStructureWriteControllerProvider.notifier)
        .run(
          () => _isEditing
              ? repository.updateSection(
                  section,
                  updatedBy: widget.currentUserId,
                )
              : repository
                    .createSection(section, createdBy: widget.currentUserId)
                    .then((_) {}),
        );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(academicStructureWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save the section.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _capacity.dispose();
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
            _isEditing ? 'Edit section' : 'Add section',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Section name',
              hintText: 'e.g. A',
            ),
            validator: (v) => Validators.required(v, fieldName: 'Section name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Code (optional)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _capacity,
            decoration: const InputDecoration(labelText: 'Capacity (optional)'),
            keyboardType: TextInputType.number,
            validator: (v) =>
                v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null
                ? null
                : 'Enter a whole number.',
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
