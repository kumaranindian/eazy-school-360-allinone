import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// One figure in a [StatChipsBar].
class StatChip {
  final String label;

  /// Null while the count is still loading (shown as a placeholder).
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  const StatChip({
    required this.label,
    required this.count,
    this.selected = false,
    this.onTap,
  });
}

/// A slim row of headline numbers that double as quick filters: tap one to
/// narrow the list below to it. On a phone the row scrolls sideways so it
/// never takes more than one line of the screen.
class StatChipsBar extends StatelessWidget {
  final List<StatChip> chips;

  const StatChipsBar({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            _chip(theme, chips[i]),
          ],
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, StatChip chip) {
    final scheme = theme.colorScheme;
    final count = chip.count?.toString() ?? '–';
    return Semantics(
      button: chip.onTap != null,
      selected: chip.selected,
      label: '${chip.label}: $count',
      excludeSemantics: true,
      child: Material(
        color: chip.selected ? scheme.primaryContainer : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: chip.selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: chip.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: chip.selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  chip.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: chip.selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
