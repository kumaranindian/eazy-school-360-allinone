import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// A titled group of [HubTile]s laid out as a grid that follows the width it
/// is given (1 column on a phone, 2 on a tablet, 3+ on a desktop) and the
/// user's text size: every row is as tall as its tallest tile, so nothing is
/// clipped at large fonts and tiles in a row line up.
class HubGroup extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> tiles;

  /// Narrowest a tile may get before the grid drops a column.
  final double minTileWidth;

  const HubGroup({
    super.key,
    required this.title,
    required this.tiles,
    this.subtitle,
    this.minTileWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: text.titleMedium)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            var columns = (constraints.maxWidth / minTileWidth).floor().clamp(
              1,
              4,
            );
            if (columns > tiles.length) columns = tiles.length;
            // Avoid a single orphan tile on the last row (4 tiles as 3 + 1):
            // one column fewer reads as a balanced grid (2 + 2).
            if (columns > 1 && tiles.length % columns == 1) columns -= 1;
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0) const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: i + c < tiles.length
                                ? tiles[i + c]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Tone of a [HubTile]'s status badge.
enum HubBadgeTone { success, warning, neutral }

/// A navigation tile for a hub page: an icon, a title, a one-line
/// description, an optional status badge and a chevron. The whole tile is the
/// tap target.
class HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback onTap;
  final String? badge;
  final HubBadgeTone badgeTone;

  /// Tints the icon tile (a module's own colour) instead of the default
  /// primary container.
  final Color? accent;

  /// A module that is planned but not built yet: shown dimmed with a
  /// "Coming soon" badge and no chevron. [onTap] still runs (to say so).
  final bool comingSoon;

  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.description,
    this.badge,
    this.badgeTone = HubBadgeTone.neutral,
    this.accent,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = comingSoon ? scheme.outline : accent;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint != null
                      ? tint.withValues(alpha: 0.14)
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: tint ?? scheme.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: comingSoon ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (comingSoon) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const HubBadge(
                        label: 'Coming soon',
                        icon: Icons.hourglass_top,
                      ),
                    ] else if (badge != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      HubBadge(label: badge!, tone: badgeTone),
                    ],
                  ],
                ),
              ),
              if (!comingSoon) ...[
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(Icons.chevron_right, color: scheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small status pill. Colour is never the only signal: the label says it.
class HubBadge extends StatelessWidget {
  final String label;
  final HubBadgeTone tone;
  final IconData? icon;

  const HubBadge({
    super.key,
    required this.label,
    this.tone = HubBadgeTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = switch (tone) {
      HubBadgeTone.success => AppColors.success,
      HubBadgeTone.warning => AppColors.warning,
      HubBadgeTone.neutral => scheme.onSurfaceVariant,
    };
    // A readable foreground in both themes: the accent itself on light,
    // a lightened tint of it on dark.
    final foreground = dark ? Color.lerp(accent, Colors.white, 0.45)! : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
