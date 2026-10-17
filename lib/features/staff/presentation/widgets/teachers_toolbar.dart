import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';

/// The search-and-filter surface of the Teachers screen: the Staff | Teachers
/// switch, the search box, the filters, and the Filters button, in one card.
///
/// - **Desktop** (and only when the width really allows): everything on one
///   row. Otherwise it falls back to the tablet arrangement rather than
///   overflowing or scrolling the page sideways.
/// - **Tablet**: row 1 the switch and the search; row 2 the filters and the
///   Filters button, wrapping as needed.
/// - **Phone**: the switch, the search and a full-width Filters button, one
///   under the other. The individual filters live in the sheet.
///
/// It owns no state. The page keeps the search text, the filter values and
/// their effects; this builds the same [FilterField]s' controls
/// ([fieldsBuilder] is read again on every build and every sheet change) and
/// reports changes through the callbacks it was given.
class TeachersToolbar extends StatelessWidget {
  final ScreenSize layout;
  final Widget switcher;

  /// The page's "⋮" menu, shown at the end of the toolbar.
  final Widget? trailing;
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final bool searchEnabled;
  final List<FilterField> Function() fieldsBuilder;

  /// How many of the first fields appear inline on tablet / desktop (the rest
  /// are only in the sheet). Every field is always in the sheet.
  final int inlineCount;

  /// An explanatory line under the controls (e.g. why search is paused).
  final String? note;

  const TeachersToolbar({
    super.key,
    required this.layout,
    required this.switcher,
    required this.searchController,
    required this.onSearchChanged,
    required this.fieldsBuilder,
    this.trailing,
    this.searchHint = 'Search',
    this.searchEnabled = true,
    this.inlineCount = 4,
    this.note,
  });

  static const double _gap = 10;
  static const double _pad = 10;
  // The narrowest a one-row desktop toolbar can be before it wraps instead:
  // switch + search + four filters + Filters button + menu + the gaps.
  static const double _switcherWidth = 200;
  static const double _minSearch = 200;
  static const double _minFilter = 140;
  static const double _filtersButton = 112;
  static const double _menu = 44;
  static const double _filterWidth = 176;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = fieldsBuilder();
    final inline = fields.take(inlineCount).toList();
    final total = fields.where((f) => f.isApplied).length;
    void openSheet() =>
        FilterBar.openFilterSheet(context, fieldsBuilder: fieldsBuilder);

    final search = FilterSearchField(
      controller: searchController,
      hint: searchHint,
      enabled: searchEnabled,
      onChanged: onSearchChanged,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_pad),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Text scaling widens the switch, the search box's chrome and the
            // button, so every width test below scales with it.
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final switcherW = _switcherWidth * scale;
            final oneRowAt =
                switcherW +
                _minSearch +
                inline.length * _minFilter * scale +
                _filtersButton * scale +
                (trailing == null ? 0 : _menu) +
                (inline.length + 3) * _gap;
            // The switch and the search side by side need room for both.
            final sideBySide =
                width >=
                switcherW + _minSearch + (trailing == null ? 0 : _menu) + _gap;
            final Widget body;
            if (layout.isMobile) {
              body = _phone(search, total, openSheet);
            } else if (layout.isDesktop && width >= oneRowAt) {
              body = _oneRow(context, search, inline, total, openSheet);
            } else {
              body = _twoRows(
                context,
                search,
                inline,
                total,
                openSheet,
                sideBySide: sideBySide,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                body,
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      note!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _phone(Widget search, int total, VoidCallback openSheet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: double.infinity, child: switcher),
        const SizedBox(height: _gap),
        search,
        const SizedBox(height: _gap),
        Row(
          children: [
            Expanded(
              child: FiltersButton(
                total: total,
                onPressed: openSheet,
                expanded: true,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }

  Widget _oneRow(
    BuildContext context,
    Widget search,
    List<FilterField> inline,
    int total,
    VoidCallback openSheet,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        switcher,
        const SizedBox(width: _gap),
        Expanded(flex: 3, child: search),
        for (final f in inline) ...[
          const SizedBox(width: _gap),
          Expanded(flex: 2, child: f.buildControl(context, true)),
        ],
        const SizedBox(width: _gap),
        FiltersButton(total: total, onPressed: openSheet),
        if (trailing != null) trailing!,
      ],
    );
  }

  Widget _twoRows(
    BuildContext context,
    Widget search,
    List<FilterField> inline,
    int total,
    VoidCallback openSheet, {
    required bool sideBySide,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sideBySide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              switcher,
              const SizedBox(width: _gap),
              Expanded(child: search),
              if (trailing != null) trailing!,
            ],
          )
        else ...[
          // Too narrow for both side by side (large text): stack them.
          Row(
            children: [
              Expanded(
                child: SizedBox(width: double.infinity, child: switcher),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: _gap),
          search,
        ],
        const SizedBox(height: _gap),
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in inline)
              SizedBox(
                width: _filterWidth,
                child: f.buildControl(context, true),
              ),
            FiltersButton(total: total, onPressed: openSheet),
          ],
        ),
      ],
    );
  }
}
