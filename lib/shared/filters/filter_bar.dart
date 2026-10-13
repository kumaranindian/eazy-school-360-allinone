import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import 'filter_field.dart';

/// The search-and-filter strip above a list, one component for every screen
/// size so list pages stop spending their whole first screen on dropdowns.
///
/// - **Phone**: a search box and a "Filters" button; every filter lives in a
///   bottom sheet, and what is applied shows as removable chips.
/// - **Tablet / desktop**: the search box plus as many filters inline as fit
///   on one row; the rest sit behind the same "Filters" button and show as
///   chips when applied.
///
/// [fieldsBuilder] is called again each time the page rebuilds *and* each
/// time the sheet changes a value, so it must read the page's current state.
class FilterBar extends StatelessWidget {
  /// Null for a filter-only bar (pages with nothing to search by).
  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;

  /// Optional control shown at the start of the search box, e.g. a
  /// "search by field" picker.
  final Widget? searchPrefix;

  final List<FilterField> Function() fieldsBuilder;

  /// False while filters cannot be used (the page is searching); the bar then
  /// explains why instead of showing chips.
  final bool filtersEnabled;
  final String pausedMessage;

  /// False when the page cannot search right now (e.g. another filter has
  /// taken over the query); the box is shown disabled.
  final bool searchEnabled;

  /// An explanatory line under the bar, shown while filters are usable.
  final String? note;

  const FilterBar({
    super.key,
    required this.fieldsBuilder,
    this.searchController,
    this.searchHint = 'Search',
    this.onSearchChanged,
    this.searchPrefix,
    this.filtersEnabled = true,
    this.searchEnabled = true,
    this.note,
    this.pausedMessage =
        'Filters are paused while searching. Clear the search to use them.',
  });

  static const double _inlineFieldWidth = 176;
  static const double _minSearchWidth = 240;
  static const double _filtersButtonWidth = 120;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = fieldsBuilder();
        final width = constraints.maxWidth;

        // How many filters fit beside the search box on one row. Phones get
        // none: the search box takes the row and filters open in a sheet.
        final minSearch = searchController == null ? 0.0 : _minSearchWidth;
        var inlineCount = 0;
        if (width >= 600) {
          final room = width - minSearch - _filtersButtonWidth;
          inlineCount = (room / (_inlineFieldWidth + AppSpacing.sm))
              .floor()
              .clamp(0, fields.length);
          // If everything fits, no Filters button is needed, which frees room.
          if (inlineCount < fields.length) {
            // keep the button
          } else {
            inlineCount =
                ((width - minSearch) / (_inlineFieldWidth + AppSpacing.sm))
                    .floor()
                    .clamp(0, fields.length);
          }
        }
        final inline = fields.take(inlineCount).toList();
        final hidden = fields.skip(inlineCount).toList();
        final appliedHidden = hidden.where((f) => f.isApplied).toList();
        final appliedCount = fields.where((f) => f.isApplied).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: searchController == null
                      ? const SizedBox.shrink()
                      : _searchField(context),
                ),
                for (final f in inline) ...[
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: _inlineFieldWidth,
                    child: f.controlBuilder(context, filtersEnabled),
                  ),
                ],
                if (hidden.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _filtersButton(
                    context,
                    count: hidden.where((f) => f.isApplied).length,
                    total: appliedCount,
                  ),
                ],
              ],
            ),
            if (!filtersEnabled)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  pausedMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  note!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (filtersEnabled && appliedHidden.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final f in appliedHidden)
                      InputChip(
                        label: Text('${f.label}: ${f.appliedLabel}'),
                        onDeleted: f.onClear,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (appliedHidden.length > 1)
                      TextButton(
                        onPressed: () {
                          for (final f in appliedHidden) {
                            f.onClear();
                          }
                        },
                        child: const Text('Clear all'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _searchField(BuildContext context) {
    final controller = searchController!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => TextField(
        controller: controller,
        enabled: searchEnabled,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: searchHint,
          isDense: true,
          prefixIcon:
              searchPrefix ?? const Icon(Icons.search, semanticLabel: 'Search'),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onSearchChanged?.call('');
                  },
                ),
        ),
        onChanged: onSearchChanged,
      ),
    );
  }

  Widget _filtersButton(
    BuildContext context, {
    required int count,
    required int total,
  }) {
    // The count covers every active filter, inline ones included, so the
    // button never says "no filters" while a list is filtered.
    final label = total > 0 ? 'Filters · $total' : 'Filters';
    // On a very narrow screen, or with large text, the labelled button would
    // squeeze the search box; an icon with a count badge keeps its width fixed.
    final compact =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    if (compact) {
      return IconButton.filledTonal(
        tooltip: label,
        onPressed: filtersEnabled ? () => _openSheet(context) : null,
        icon: Badge(
          isLabelVisible: total > 0,
          label: Text('$total'),
          child: const Icon(Icons.tune),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: FilledButton.tonalIcon(
        onPressed: filtersEnabled ? () => _openSheet(context) : null,
        icon: const Icon(Icons.tune, size: 20),
        label: Text(label),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Re-read on every change: the page owns the values.
          final fields = fieldsBuilder();
          void rebuild() => setSheetState(() {});
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filters',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: fields.any((f) => f.isApplied)
                            ? () {
                                for (final f in fields) {
                                  f.onClear();
                                }
                                rebuild();
                              }
                            : null,
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final f in fields) ...[
                    f.controlBuilder(context, filtersEnabled),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
