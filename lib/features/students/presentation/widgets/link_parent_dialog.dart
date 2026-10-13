import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/parent.dart';
import '../../domain/relationship_type.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';

/// Links a parent/guardian to a student (brief §9) — either an existing
/// parent record (searched by name) or a newly-created one, then sets the
/// relationship's type/primary/emergency-contact/portal-access flags.
/// Reused from both the admission wizard's "Parent/Guardian" step and the
/// student profile page's "Add parent" action.
class LinkParentDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String studentId;
  final String currentUserId;
  final Set<String> alreadyLinkedParentIds;

  const LinkParentDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.studentId,
    required this.currentUserId,
    this.alreadyLinkedParentIds = const {},
  });

  @override
  ConsumerState<LinkParentDialog> createState() => _LinkParentDialogState();
}

class _LinkParentDialogState extends ConsumerState<LinkParentDialog> {
  bool _isNewParent = false;
  final _searchController = TextEditingController();
  List<Parent> _searchResults = const [];
  bool _searching = false;
  Parent? _selected;

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  RelationshipType _relationshipType = RelationshipType.guardian;
  bool _isPrimary = false;
  bool _isEmergencyContact = false;
  bool _canAccessPortal = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    setState(() => _searching = true);
    final page = await ref
        .read(parentRepositoryProvider)
        .searchParentsByName(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          query: query.trim(),
        );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchResults = page.items
          .where((p) => !widget.alreadyLinkedParentIds.contains(p.parentId))
          .toList();
    });
  }

  Future<void> _submit() async {
    final studentController = ref.read(studentWriteControllerProvider.notifier);
    var parentId = _selected?.parentId;

    if (_isNewParent) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      final newParent = Parent(
        parentId: '',
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        status: ActivationStatus.active,
      );
      parentId = await ref
          .read(parentWriteControllerProvider.notifier)
          .createParent(newParent, createdBy: widget.currentUserId);
      if (parentId == null) {
        if (!mounted) return;
        final error = ref.read(parentWriteControllerProvider).error;
        context.showSnackBar(
          error == null
              ? 'Unable to create this parent.'
              : userMessageFor(error),
          isError: true,
        );
        return;
      }
    }

    if (parentId == null) {
      if (!mounted) return;
      context.showSnackBar(
        'Please select or add a parent first.',
        isError: true,
      );
      return;
    }

    final success = await studentController.linkParent(
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      studentId: widget.studentId,
      parentId: parentId,
      relationshipType: _relationshipType,
      isPrimary: _isPrimary,
      isEmergencyContact: _isEmergencyContact,
      canAccessPortal: _canAccessPortal,
      createdBy: widget.currentUserId,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to link this parent.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving =
        ref.watch(studentWriteControllerProvider).isLoading ||
        ref.watch(parentWriteControllerProvider).isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add parent / guardian', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Existing parent')),
              ButtonSegment(value: true, label: Text('New parent')),
            ],
            selected: {_isNewParent},
            onSelectionChanged: (s) => setState(() => _isNewParent = s.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_isNewParent) ...[
            TextFormField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (v) => Validators.required(v, fieldName: 'First name'),
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
          ] else ...[
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search parents by name',
              ),
              onChanged: _search,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_searching) const LinearProgressIndicator(),
            if (!_searching && _searchResults.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final parent in _searchResults)
                      RadioListTile<Parent>(
                        value: parent,
                        groupValue: _selected,
                        onChanged: (p) => setState(() => _selected = p),
                        title: Text(parent.displayName),
                        subtitle: Text(parent.phone),
                        dense: true,
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<RelationshipType>(
            isExpanded: true,
            value: _relationshipType,
            decoration: const InputDecoration(labelText: 'Relationship'),
            items: [
              for (final t in RelationshipType.values)
                DropdownMenuItem(value: t, child: Text(t.displayName)),
            ],
            onChanged: (value) =>
                setState(() => _relationshipType = value ?? _relationshipType),
          ),
          CheckboxListTile(
            value: _isPrimary,
            onChanged: (v) => setState(() => _isPrimary = v ?? false),
            title: const Text('Primary contact'),
            subtitle: const Text('Used for communication and notifications'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _isEmergencyContact,
            onChanged: (v) => setState(() => _isEmergencyContact = v ?? false),
            title: const Text('Emergency contact'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _canAccessPortal,
            onChanged: (v) => setState(() => _canAccessPortal = v ?? false),
            title: const Text('Allow parent portal access'),
            subtitle: const Text(
              'A login account is set up separately by an admin',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.md),
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
