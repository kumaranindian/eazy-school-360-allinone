import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_admin_providers.dart';

/// Adds a platform administrator. No password is ever entered: the person is
/// emailed a link to choose their own, and must set up two-step verification
/// at first sign-in.
class AddPlatformAdminDialog extends ConsumerStatefulWidget {
  const AddPlatformAdminDialog({super.key});

  @override
  ConsumerState<AddPlatformAdminDialog> createState() =>
      _AddPlatformAdminDialogState();
}

class _AddPlatformAdminDialogState
    extends ConsumerState<AddPlatformAdminDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  PlatformRole _role = PlatformRole.support;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final result = await ref
        .read(platformAdminActionsProvider.notifier)
        .create(name: _name.text, email: _email.text, role: _role);
    if (!mounted) return;
    if (result == null) {
      setState(
        () => _error = userMessageFor(
          ref.read(platformAdminActionsProvider).error!,
        ),
      );
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformAdminActionsProvider).isLoading;
    return AlertDialog(
      title: const Text('Add platform administrator'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('pa-name'),
                  controller: _name,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v ?? '').trim().length < 2
                      ? 'Enter the full name'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('pa-email'),
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Company email'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(t)
                        ? null
                        : 'Enter a valid email address';
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<PlatformRole>(
                  key: const ValueKey('pa-role'),
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  isExpanded: true,
                  items: [
                    for (final r in PlatformRole.values)
                      DropdownMenuItem(value: r, child: Text(r.displayName)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _role = v ?? _role),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _role.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'They will get an email to choose a password, and must set up '
                  'two-step verification at first sign-in.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pa-save'),
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
