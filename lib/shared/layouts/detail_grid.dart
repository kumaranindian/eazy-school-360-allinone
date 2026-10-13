import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// One label/value pair of a [DetailGrid].
class DetailItem {
  final String label;
  final String value;
  final IconData? icon;

  const DetailItem(this.label, this.value, {this.icon});
}

/// Read-only "label over value" details that flow into as many columns as
/// fit (one on a phone, two or three on wider screens) instead of a single
/// long list of "Label: value" lines. Empty values are skipped so a profile
/// never shows a column of dashes.
class DetailGrid extends StatelessWidget {
  final List<DetailItem> items;
  final double minColumnWidth;

  const DetailGrid({super.key, required this.items, this.minColumnWidth = 240});

  @override
  Widget build(BuildContext context) {
    final shown = items.where((i) => i.value.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minColumnWidth).floor().clamp(
          1,
          3,
        );
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.lg) / columns;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in shown)
              SizedBox(
                width: width,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            item.value,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
