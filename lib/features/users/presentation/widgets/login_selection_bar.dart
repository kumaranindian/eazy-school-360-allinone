import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// The strip shown above a directory while choosing people to give logins:
/// how many are ticked, select/clear the loaded page, and the action.
class LoginSelectionBar extends StatelessWidget {
  final int selected;
  final int selectable;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  /// Defaults describe giving logins; reset-password selection overrides them.
  final String actionLabel;
  final IconData actionIcon;
  final String? selectAllLabel;

  const LoginSelectionBar({
    super.key,
    required this.selected,
    required this.selectable,
    required this.onSelectAll,
    required this.onClear,
    required this.onCreate,
    required this.onCancel,
    this.actionLabel = 'Give login access',
    this.actionIcon = Icons.vpn_key_outlined,
    this.selectAllLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$selected selected',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          TextButton(
            onPressed: selected < selectable ? onSelectAll : null,
            child: Text(
              selectAllLabel ?? 'Select all ($selectable without a login)',
            ),
          ),
          TextButton(
            onPressed: selected > 0 ? onClear : null,
            child: const Text('Clear'),
          ),
          FilledButton.icon(
            onPressed: selected > 0 ? onCreate : null,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
