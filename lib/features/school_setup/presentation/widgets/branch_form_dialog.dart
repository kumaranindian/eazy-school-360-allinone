import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/branch.dart';
import '../../domain/branch_status.dart';
import '../providers/school_profile_providers.dart';

/// Create/edit form for a [Branch], shown inside
/// `showAdaptiveAppDialog` by `branches_page.dart`. Pass [existing] to
/// edit; omit it to create a new branch.
class BranchFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String currentUserId;
  final Branch? existing;
  final List<Branch> siblingsForValidation;

  const BranchFormDialog({
    super.key,
    required this.schoolId,
    required this.currentUserId,
    this.existing,
    required this.siblingsForValidation,
  });

  @override
  ConsumerState<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends ConsumerState<BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _addressLine1 = TextEditingController(
    text: widget.existing?.addressLine1,
  );
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _state = TextEditingController(text: widget.existing?.state);
  late BranchStatus _status = widget.existing?.status ?? BranchStatus.active;

  bool get _isEditing => widget.existing != null;

  String? _validateCode(String? value) {
    final requiredError = Validators.required(value, fieldName: 'Branch code');
    if (requiredError != null) return requiredError;
    final duplicate = widget.siblingsForValidation.any(
      (b) =>
          b.branchId != widget.existing?.branchId &&
          b.code?.toLowerCase() == value!.trim().toLowerCase(),
    );
    if (duplicate) return 'This branch code is already used by another branch.';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final branch = Branch(
      branchId: widget.existing?.branchId ?? '',
      schoolId: widget.schoolId,
      name: _name.text.trim(),
      code: _code.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      addressLine1: _addressLine1.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      status: _status,
    );

    final controller = ref.read(schoolProfileWriteControllerProvider.notifier);
    final success = _isEditing
        ? await controller.updateBranch(branch, updatedBy: widget.currentUserId)
        : await controller.createBranch(
            branch,
            createdBy: widget.currentUserId,
          );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(schoolProfileWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save the branch. Please try again.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _code,
      _email,
      _phone,
      _addressLine1,
      _city,
      _state,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(schoolProfileWriteControllerProvider).isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? 'Edit branch' : 'Add branch',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Branch name'),
            validator: (v) => Validators.required(v, fieldName: 'Branch name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Branch code'),
            validator: _validateCode,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) =>
                v == null || v.isEmpty ? null : Validators.email(v),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _addressLine1,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: _state,
                  decoration: const InputDecoration(labelText: 'State'),
                ),
              ),
            ],
          ),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<BranchStatus>(
              isExpanded: true,
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in BranchStatus.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(s.name == 'active' ? 'Active' : 'Inactive'),
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
