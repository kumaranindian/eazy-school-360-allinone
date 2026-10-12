import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../users/domain/user_profile.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../domain/staff.dart';
import '../providers/staff_providers.dart';

/// Links the staff record to an application account by the account's user
/// ID (== its Firebase Auth uid) — never by email, which can change. The
/// admin looks the ID up first so they confirm *who* they are linking.
/// A staff member does not need an account; unlinking is always possible.
class LinkUserDialog extends ConsumerStatefulWidget {
  final Staff staff;
  final String currentUserId;

  const LinkUserDialog({
    super.key,
    required this.staff,
    required this.currentUserId,
  });

  @override
  ConsumerState<LinkUserDialog> createState() => _LinkUserDialogState();
}

class _LinkUserDialogState extends ConsumerState<LinkUserDialog> {
  final _userId = TextEditingController();
  UserProfile? _found;
  String? _lookupError;
  bool _isLookingUp = false;

  Future<void> _lookup() async {
    final id = _userId.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _isLookingUp = true;
      _found = null;
      _lookupError = null;
    });
    try {
      final profile = await ref.read(userRepositoryProvider).getUserProfile(id);
      if (!mounted) return;
      setState(() {
        if (profile == null || profile.schoolId != widget.staff.schoolId) {
          _lookupError = 'No user account with that ID exists in this school.';
        } else {
          _found = profile;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _lookupError = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _save(String? userId) async {
    final success = await ref
        .read(staffWriteControllerProvider.notifier)
        .linkUser(widget.staff, userId, updatedBy: widget.currentUserId);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(staffWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to update the account link.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(staffWriteControllerProvider).isLoading;
    final currentlyLinked = widget.staff.userId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Application account', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Link this staff record to a user who signs in to the app. A staff member can exist without an account. '
          "The account's role, not the designation, decides what they can do.",
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (currentlyLinked != null) ...[
          Text('Linked account ID: $currentlyLinked'),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: isSaving ? null : () => _save(null),
            child: const Text('Unlink account'),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
        ],
        TextField(
          controller: _userId,
          decoration: InputDecoration(
            labelText: currentlyLinked == null
                ? 'User ID'
                : 'Link a different user ID',
            suffixIcon: _isLookingUp
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Look up',
                    onPressed: _lookup,
                  ),
          ),
          onSubmitted: (_) => _lookup(),
        ),
        if (_lookupError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _lookupError!,
              style: TextStyle(color: context.colors.error),
            ),
          ),
        if (_found != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_found!.name),
              subtitle: Text('${_found!.email} · ${_found!.role.displayName}'),
            ),
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
              onPressed: isSaving || _found == null
                  ? null
                  : () => _save(_found!.userId),
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Link account'),
            ),
          ],
        ),
      ],
    );
  }
}
