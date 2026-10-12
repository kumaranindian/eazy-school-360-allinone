import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/department.dart';
import '../../domain/designation.dart';
import '../providers/staff_providers.dart';
import 'staff_config_entry.dart';

/// Create/edit a department or designation. The code is typed once at
/// creation and then fixed (it is the document id and the uniqueness key);
/// name, description and active/inactive stay editable.
class StaffConfigFormDialog extends ConsumerStatefulWidget {
  final StaffConfigKind kind;
  final String schoolId;
  final String branchId;
  final String currentUserId;
  final StaffConfigEntry? existing;

  const StaffConfigFormDialog({
    super.key,
    required this.kind,
    required this.schoolId,
    required this.branchId,
    required this.currentUserId,
    this.existing,
  });

  @override
  ConsumerState<StaffConfigFormDialog> createState() =>
      _StaffConfigFormDialogState();
}

class _StaffConfigFormDialogState extends ConsumerState<StaffConfigFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late bool _isActive =
      (widget.existing?.status ?? ActivationStatus.active) ==
      ActivationStatus.active;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final status = _isActive
        ? ActivationStatus.active
        : ActivationStatus.inactive;
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text.trim();
    final code = _code.text.trim();
    final name = _name.text.trim();
    final userId = widget.currentUserId;

    final success = await ref
        .read(staffSetupWriteControllerProvider.notifier)
        .run((repository) async {
          switch (widget.kind) {
            case StaffConfigKind.department:
              final department = Department(
                departmentId: widget.existing?.id ?? Department.idForCode(code),
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                name: name,
                code: code,
                description: description,
                status: status,
              );
              if (_isEditing) {
                await repository.updateDepartment(
                  department,
                  updatedBy: userId,
                );
              } else {
                await repository.createDepartment(
                  department,
                  createdBy: userId,
                );
              }
            case StaffConfigKind.designation:
              final designation = Designation(
                designationId:
                    widget.existing?.id ?? Designation.idForCode(code),
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                name: name,
                code: code,
                description: description,
                status: status,
              );
              if (_isEditing) {
                await repository.updateDesignation(
                  designation,
                  updatedBy: userId,
                );
              } else {
                await repository.createDesignation(
                  designation,
                  createdBy: userId,
                );
              }
          }
        });

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(staffSetupWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save this ${widget.kind.singular.toLowerCase()}.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(staffSetupWriteControllerProvider).isLoading;
    final label = widget.kind.singular;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing
                ? 'Edit ${label.toLowerCase()}'
                : 'Add ${label.toLowerCase()}',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _code,
            enabled: !_isEditing,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '$label code',
              helperText: _isEditing
                  ? 'The code cannot be changed.'
                  : 'e.g. ${widget.kind == StaffConfigKind.department ? 'ADMIN' : 'PRINCIPAL'} — letters, digits, - or _',
            ),
            validator: (v) {
              final required = Validators.required(v, fieldName: 'Code');
              if (required != null) return required;
              if (!Department.codePattern.hasMatch(v!.trim())) {
                return '2-20 letters, digits, "-" or "_".';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: '$label name'),
            validator: (v) => Validators.required(v, fieldName: 'Name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 2,
          ),
          if (_isEditing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text(
                'Inactive entries cannot be chosen for new staff, but stay on existing records.',
              ),
              value: _isActive,
              onChanged: isSaving
                  ? null
                  : (value) => setState(() => _isActive = value),
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
