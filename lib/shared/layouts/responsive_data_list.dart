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

  /// Indexes into [columnHeaders] / [cellsBuilder] to keep on a tablet
  /// (narrower than the desktop breakpoint); desktop shows every column. When
  /// null the table keeps all columns and scrolls sideways if it must.
  final List<int>? tabletColumns;

  const ResponsiveDataList({
    super.key,
    required this.items,
    required this.columnHeaders,
    required this.cellsBuilder,
    required this.cardBuilder,
    required this.emptyState,
    this.tabletColumns,
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

        // Tablet-width tables keep only the key columns; desktop shows all.
        final keep = screenSize.isTablet && tabletColumns != null
            ? tabletColumns!
            : List<int>.generate(columnHeaders.length, (i) => i);

        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Fill the width this panel actually has (not the window's:
                // the navigation sidebar takes some of it), so the table only
                // scrolls sideways when its columns really do not fit.
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth - AppSpacing.md * 2,
                ),
                // A bordered, rounded surface so the table reads as one
                // object rather than loose rows on the page background.
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
                      // The same compact table as the staff directories: a
                      // slim muted header and 46px rows, with column gaps that
                      // fit a normal window without sideways scrolling.
                      headingRowHeight: 36,
                      dataRowMinHeight: 46,
                      dataRowMaxHeight: 56,
                      columnSpacing: 20,
                      horizontalMargin: AppSpacing.md,
                      dividerThickness: 1,
                      headingTextStyle: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(
                            fontSize: 12,
                            letterSpacing: 0.4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                      dataTextStyle: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                      columns: [
                        for (final i in keep)
                          DataColumn(label: Text(columnHeaders[i])),
                      ],
                      rows: [
                        for (final item in items)
                          DataRow(
                            cells: () {
                              final cells = cellsBuilder(item);
                              return [for (final i in keep) cells[i]];
                            }(),
                          ),
                      ],
                    ),
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
