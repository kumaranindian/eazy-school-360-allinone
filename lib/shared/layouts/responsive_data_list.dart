import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive.dart';

/// The "desktop: table, mobile: cards" pattern this milestone's
/// school/branch/academic-year/class/subject/holiday lists all need —
/// written once here instead of five times. Never horizontally scrolls
/// the whole page: the table itself scrolls if it's ever wider than the
/// viewport, the page around it doesn't.
class ResponsiveDataList<T> extends StatelessWidget {
  final List<T> items;
  final List<String> columnHeaders;
  final List<DataCell> Function(T item) cellsBuilder;
  final Widget Function(T item) cardBuilder;
  final Widget emptyState;

  const ResponsiveDataList({
    super.key,
    required this.items,
    required this.columnHeaders,
    required this.cellsBuilder,
    required this.cardBuilder,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return emptyState;

    return ResponsiveBuilder(
      builder: (context, screenSize) {
        if (screenSize.isMobile) {
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => cardBuilder(items[index]),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth:
                    MediaQuery.sizeOf(context).width - (AppSpacing.md * 2) - 32,
              ),
              // A bordered, rounded surface so the table reads as one object
              // rather than loose rows on the page background.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: DataTable(
                    columns: [
                      for (final header in columnHeaders)
                        DataColumn(label: Text(header)),
                    ],
                    rows: [
                      for (final item in items)
                        DataRow(cells: cellsBuilder(item)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
