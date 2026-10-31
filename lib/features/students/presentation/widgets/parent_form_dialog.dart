import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/parent.dart';
import '../../domain/parent_duplicates.dart';
import '../providers/parent_providers.dart';
import 'parent_duplicates_dialog.dart';

/// How [ParentFormDialog] closed (null: cancelled).
class ParentFormResult {
  final String parentId;

  /// False when the person chose an existing parent instead of adding one.
  final bool created;

  /// "Give login access now" was ticked on a new parent.
  final bool giveLogin;

  final String name;
  final String? email;

  const ParentFormResult({
    required this.parentId,
    required this.name,
    this.email,
    this.created = true,
    this.giveLogin = false,
  });
}

/// Create/edit a Parent/Guardian contact record (brief §8). Children are
/// linked from the student profile / admission. Before saving, an existing
/// parent of the branch with the same email (refused) or phone (asked) is
/// shown, so one person keeps one record and one login. A new parent can
/// be given a login straight after saving ([ParentFormResult.giveLogin]);
/// the caller opens the server-backed "Give login access" dialog.
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

  bool _giveLogin = false;
  bool _checking = false;

  /// False when the person went back to change details (or picked an
  /// existing parent, in which case the dialog has closed).
  Future<bool> _noDuplicates() async {
    setState(() => _checking = true);
    List<ParentMatch> matches;
    try {
      matches = await ref
          .read(parentDuplicateFinderProvider)
          .find(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            email: _email.text,
            phone: _phone.text,
            displayName: _isEditing
                ? ''
                : '${_firstName.text.trim()} ${_lastName.text.trim()}',
            excludeParentId: widget.existing?.parentId,
          );
    } catch (error) {
      if (mounted) {
        setState(() => _checking = false);
        context.showSnackBar(
          'Could not check for an existing parent: ${userMessageFor(error)}',
          isError: true,
        );
      }
      return false;
    }
    if (!mounted) return false;
    setState(() => _checking = false);
    // Editing: only a clash of email matters (another record's sign-in).
    if (_isEditing) matches = matches.where((m) => m.blocksCreate).toList();
    if (matches.isEmpty) return true;
    final choice = await showParentDuplicatesDialog(
      context: context,
      matches: matches,
      useLabel: _isEditing ? 'Open this parent' : 'Use this parent',
    );
    if (!mounted) return false;
    switch (choice) {
      case UseExistingParent(:final parent):
        Navigator.of(context).pop(
          ParentFormResult(
            parentId: parent.parentId,
            name: parent.displayName,
            email: parent.email,
            created: false,
          ),
        );
        return false;
      case CreateParentAnyway():
        return true;
      case null:
        return false;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!await _noDuplicates()) return;

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
      // Lowercase, as bulk import saves it: it becomes the sign-in email.
      email: ParentContact.normalizeEmail(_email.text),
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
    final savedId = _isEditing
        ? (await controller.updateParent(
                parent,
                updatedBy: widget.currentUserId,
              ))
              ? parent.parentId
              : null
        : await controller.createParent(
            parent,
            createdBy: widget.currentUserId,
          );

    if (!mounted) return;
    if (savedId != null) {
      Navigator.of(context).pop(
        ParentFormResult(
          parentId: savedId,
          name: parent.displayName,
          email: parent.email,
          created: !_isEditing,
          giveLogin: !_isEditing && _giveLogin,
        ),
      );
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
    final isSaving =
        ref.watch(parentWriteControllerProvider).isLoading || _checking;

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
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              helperText: 'Needed for a parent login. One email per parent.',
              helperMaxLines: 3,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? null : Validators.email(v),
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
          if (!_isEditing)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _giveLogin,
              onChanged: isSaving
                  ? null
                  : (v) => setState(() => _giveLogin = v ?? false),
              title: const Text('Give login access after saving'),
              subtitle: const Text(
                'You choose how the first password is set. Needs an email.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
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
