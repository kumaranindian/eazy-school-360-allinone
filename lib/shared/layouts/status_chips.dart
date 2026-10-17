import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive.dart';
import '../filters/filter_field.dart';
import 'stat_chips.dart';

/// The compact summary row above a list: headline counts that double as
/// quick filters, and the filters currently applied as removable tags.
///
/// - **Tablet / desktop**: one row; the counts at the start, the applied tags
///   at the right. It wraps only when the width really requires it.
/// - **Phone**: the counts scroll sideways (a chip never wraps onto a second
///   line), and the tags sit below them.
///
/// Pure presentation: the counts and their callbacks come from the page (the
/// same [StatChip]s [StatChipsBar] takes), and a tag clears through its
/// [FilterField.onClear], the filter's own supported behaviour.
class StatusChips extends StatelessWidget {
  final List<StatChip> chips;

  /// Applied filters to show as tags; unapplied ones are ignored.
  final List<FilterField> activeFilters;
  final ScreenSize layout;

  const StatusChips({
    super.key,
    required this.chips,
    this.activeFilters = const [],
    required this.layout,
  });

  /// The visible height of a chip; on a phone its tap area grows to 44.
  static const double chipHeight = 32;

  @override
  Widget build(BuildContext context) {
    final tags = [
      for (final f in activeFilters)
        if (f.isApplied) f,
    ];
    final tagWidgets = [
      for (final f in tags)
        InputChip(
          label: Text('${f.label}: ${f.appliedLabel}'),
          onDeleted: f.onClear,
          visualDensity: VisualDensity.compact,
        ),
    ];
    final row = <Widget>[
      for (var i = 0; i < chips.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.sm),
        _Chip(chip: chips[i], phone: layout.isMobile),
      ],
    ];

    if (layout.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: row),
          ),
          if (tagWidgets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: tagWidgets,
            ),
          ],
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Wraps (rather than clips) when large text makes the counts wider
        // than the space.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final c in chips) _Chip(chip: c, phone: false)],
        ),
        if (tagWidgets.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: tagWidgets,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final StatChip chip;
  final bool phone;

  const _Chip({required this.chip, required this.phone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = chip.valueText ?? chip.count?.toString() ?? '–';
    final fg = chip.selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = chip.selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Semantics(
      button: chip.onTap != null,
      selected: chip.selected,
      label: '${chip.label}: $count',
      excludeSemantics: true,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: chip.onTap,
        // The pill stays 32 tall; on a phone the touch area grows to 44 by
        // padding around it (a Center would stretch the chip to full width).
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: phone ? 6 : 0),
          // Ink (not Container) so the tap ripple shows above the pill's fill.
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: ShapeDecoration(
              color: chip.selected ? scheme.primaryContainer : scheme.surface,
              shape: StadiumBorder(
                side: BorderSide(
                  color: chip.selected ? scheme.primary : scheme.outlineVariant,
                ),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: StatusChips.chipHeight,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count,
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    chip.label,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
