import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/subject.dart';
import '../../domain/subject_type.dart';
import '../providers/academic_structure_providers.dart';

class SubjectFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String currentUserId;
  final int nextDisplayOrder;
  final Subject? existing;

  const SubjectFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.currentUserId,
    required this.nextDisplayOrder,
    this.existing,
  });

  @override
  ConsumerState<SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends ConsumerState<SubjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _shortName = TextEditingController(
    text: widget.existing?.shortName,
  );
  late SubjectType _type = widget.existing?.type ?? SubjectType.core;
  late ActivationStatus _status =
      widget.existing?.status ?? ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final subject = Subject(
      subjectId: widget.existing?.subjectId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: widget.academicYearId,
      name: _name.text.trim(),
      code: _code.text.trim(),
      shortName: _shortName.text.trim(),
      type: _type,
      displayOrder: widget.existing?.displayOrder ?? widget.nextDisplayOrder,
      status: _status,
    );

    final repository = ref.read(academicStructureRepositoryProvider);
    final success = await ref
        .read(academicStructureWriteControllerProvider.notifier)
        .run(
          () => _isEditing
              ? repository.updateSubject(
                  subject,
                  updatedBy: widget.currentUserId,
                )
              : repository
                    .createSubject(subject, createdBy: widget.currentUserId)
                    .then((_) {}),
        );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(academicStructureWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save the subject.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _shortName.dispose();
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
            _isEditing ? 'Edit subject' : 'Add subject',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Subject name'),
            validator: (v) => Validators.required(v, fieldName: 'Subject name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _shortName,
                  decoration: const InputDecoration(labelText: 'Short name'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<SubjectType>(
            isExpanded: true,
            value: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in SubjectType.values)
                DropdownMenuItem(value: t, child: Text(t.displayName)),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
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
