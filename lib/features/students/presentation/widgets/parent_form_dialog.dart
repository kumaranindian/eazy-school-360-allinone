import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/parent.dart';
import '../providers/parent_providers.dart';

/// Create/edit a Parent/Guardian contact record (brief §8). Portal access
/// and children are managed elsewhere (Parent profile page) — this dialog
/// is contact information only.
class ParentFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String currentUserId;
  final Parent? existing;

  const ParentFormDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.currentUserId,
    this.existing,
  });

  @override
  ConsumerState<ParentFormDialog> createState() => _ParentFormDialogState();
}

class _ParentFormDialogState extends ConsumerState<ParentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(
    text: widget.existing?.firstName,
  );
  late final _middleName = TextEditingController(
    text: widget.existing?.middleName,
  );
  late final _lastName = TextEditingController(text: widget.existing?.lastName);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _alternatePhone = TextEditingController(
    text: widget.existing?.alternatePhone,
  );
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _occupation = TextEditingController(
    text: widget.existing?.occupation,
  );
  late final _addressLine1 = TextEditingController(
    text: widget.existing?.addressLine1,
  );
  late final _city = TextEditingController(text: widget.existing?.city);

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final parent = Parent(
      parentId: widget.existing?.parentId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      firstName: _firstName.text.trim(),
      middleName: _middleName.text.trim().isEmpty
          ? null
          : _middleName.text.trim(),
      lastName: _lastName.text.trim(),
      phone: _phone.text.trim(),
      alternatePhone: _alternatePhone.text.trim().isEmpty
          ? null
          : _alternatePhone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      occupation: _occupation.text.trim().isEmpty
          ? null
          : _occupation.text.trim(),
      addressLine1: _addressLine1.text.trim().isEmpty
          ? null
          : _addressLine1.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      status: widget.existing?.status ?? ActivationStatus.active,
    );

    final controller = ref.read(parentWriteControllerProvider.notifier);
    final success = _isEditing
        ? await controller.updateParent(parent, updatedBy: widget.currentUserId)
        : (await controller.createParent(
                parent,
                createdBy: widget.currentUserId,
              )) !=
              null;

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(parentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save this parent.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _middleName,
      _lastName,
      _phone,
      _alternatePhone,
      _email,
      _occupation,
      _addressLine1,
      _city,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(parentWriteControllerProvider).isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? 'Edit parent / guardian' : 'Add parent / guardian',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: 'First name'),
            validator: (v) => Validators.required(v, fieldName: 'First name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _middleName,
            decoration: const InputDecoration(
              labelText: 'Middle name (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: 'Last name'),
            validator: (v) => Validators.required(v, fieldName: 'Last name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
            validator: (v) => Validators.phone(v, required: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _alternatePhone,
            decoration: const InputDecoration(
              labelText: 'Alternate phone (optional)',
            ),
            keyboardType: TextInputType.phone,
            validator: Validators.phone,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _occupation,
            decoration: const InputDecoration(
              labelText: 'Occupation (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _addressLine1,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City (optional)'),
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
