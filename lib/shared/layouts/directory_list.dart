import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive.dart';

/// Page padding and the gap between sections, by layout — one definition for
/// every directory screen (staff, teachers, students, parents).
abstract final class DirectoryLayout {
  /// One 16px gutter on every size, the same as the rest of the app's pages
  /// and the shell's hero, so edges line up from screen to screen.
  static double pagePadding(ScreenSize l) => 16;
  static double sectionGap(ScreenSize l) => 12;

  /// The content never grows wider than this on a large display.
  static const double maxContentWidth = 1440;
}

/// Pads a directory page and keeps it to a readable width, centred.
class DirectoryFrame extends StatelessWidget {
  final double padding;

  /// The space above the content; smaller than [padding] when a hero already
  /// sits above it (the shell's), so the gap to it matches the gaps between
  /// sections.
  final double? top;
  final Widget child;

  const DirectoryFrame({
    super.key,
    required this.padding,
    this.top,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DirectoryLayout.maxContentWidth,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            top ?? padding,
            padding,
            padding,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A column of the directory table beyond the always-present name, ID and
/// status. [showAtWidth] is the table width from which it is shown: columns
/// are dropped by the width the table really has (the last ones first), never
/// by the device, and what is dropped stays one tap away on the profile.
class DirectoryColumn {
  final String header;
  final int flex;
  final double showAtWidth;

  const DirectoryColumn({
    required this.header,
    this.flex = 3,
    this.showAtWidth = 0,
  });
}

/// One person as the list shows them. The page builds these from its own rows
/// (display values already resolved); the widgets below only lay them out.
class DirectoryRow {
  final String id;
  final String name;
  final String code;

  /// One value per [DirectoryColumn], in order; null when genuinely empty
  /// ("—" in the table).
  final List<String?> values;

  /// Widgets for cells whose text is resolved by the cell itself (a class name
  /// looked up from providers); where non-null, replaces the [values] text.
  final List<Widget?>? cells;

  /// The single secondary line of a phone card, or null for none.
  final String? phoneLine;

  /// Like [phoneLine], for a detail that is a widget; wins when both are set.
  final Widget? phoneDetail;

  /// The status pill (a staff chip, a student badge...), already built by the
  /// page: this list only decides where it goes.
  final Widget statusBadge;
  final VoidCallback onTap;

  /// A selection checkbox at the start of the row, while choosing people.
  final Widget? leading;

  /// Icon buttons at the end of the row (e.g. the Login access key).
  final List<Widget> actions;

  const DirectoryRow({
    required this.id,
    required this.name,
    required this.code,
    required this.values,
    required this.phoneLine,
    this.cells,
    this.phoneDetail,
    required this.statusBadge,
    required this.onTap,
    this.leading,
    this.actions = const [],
  });

  /// "AB" from "Anil Bose": the first letters of the first and last word.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    final first = words.first;
    final last = words.length > 1 ? words.last : '';
    return '${first[0]}${last.isEmpty ? '' : last[0]}'.toUpperCase();
  }
}

/// The directory card: the table (tablet / desktop) or compact cards (phone),
/// and the "Showing N of TOTAL / Load more" footer, all in one card.
///
/// Paging stays with the page: it passes the count, whether there is more,
/// whether a load is running, and the callback — nothing here fetches.
class DirectoryListCard extends StatelessWidget {
  final List<DirectoryRow> items;
  final List<DirectoryColumn> columns;
  final String nameHeader;
  final String codeHeader;
  final ScreenSize layout;
  final Widget emptyState;

  /// The total the shown rows are part of, when the page knows it (it does not
  /// while a search or a narrowing filter has taken over the query).
  final int? total;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;

  /// A load-more failure to show under the list (the rows already there stay).
  final String? errorText;

  const DirectoryListCard({
    super.key,
    required this.items,
    required this.columns,
    this.nameHeader = 'Name',
    this.codeHeader = 'ID',
    required this.layout,
    required this.emptyState,
    required this.total,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty)
              emptyState
            else if (layout.isMobile)
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                DirectoryCard(key: ValueKey(items[i].id), item: items[i]),
              ]
            else
              DirectoryTable(
                items: items,
                columns: columns,
                nameHeader: nameHeader,
                codeHeader: codeHeader,
              ),
            if (items.isNotEmpty) ...[
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    errorText!,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const Divider(height: 1),
              _Footer(
                shown: items.length,
                total: total,
                hasMore: hasMore,
                isLoading: isLoading,
                onLoadMore: onLoadMore,
                phone: layout.isMobile,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int shown;
  final int? total;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final bool phone;

  const _Footer({
    required this.shown,
    required this.total,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The total is only known for the plain list; never invented.
    final count = Text(
      total == null || total! < shown
          ? 'Showing $shown'
          : 'Showing $shown of $total',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 13,
      ),
    );
    final button = OutlinedButton(
      onPressed: isLoading ? null : onLoadMore,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      child: isLoading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Load more'),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                count,
                if (hasMore) ...[const SizedBox(height: AppSpacing.sm), button],
              ],
            )
          : Row(
              children: [
                Expanded(child: count),
                if (hasMore) button,
              ],
            ),
    );
  }
}

/// A person's circle of initials.
class PersonAvatar extends StatelessWidget {
  final String initials;
  final double size;

  const PersonAvatar({super.key, required this.initials, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: size * 0.4 < 12 ? 12 : size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Desktop / tablet rows of about 46px.
class DirectoryTable extends StatelessWidget {
  final List<DirectoryRow> items;
  final List<DirectoryColumn> columns;
  final String nameHeader;
  final String codeHeader;

  const DirectoryTable({
    super.key,
    required this.items,
    required this.columns,
    this.nameHeader = 'Name',
    this.codeHeader = 'ID',
  });

  static const double rowMinHeight = 46;
  static const double _statusWidth = 112;
  static const double _actionWidth = 48;
  static const double _leadingWidth = 44;

  @override
  Widget build(BuildContext context) {
    final hasLeading = items.any((i) => i.leading != null);
    final actionCount = items.fold<int>(
      0,
      (m, i) => i.actions.length > m ? i.actions.length : m,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final shown = [
          for (var c = 0; c < columns.length; c++)
            if (width >= columns[c].showAtWidth) c,
        ];
        final theme = Theme.of(context);
        final headStyle = theme.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          letterSpacing: 0.4,
          color: theme.colorScheme.onSurfaceVariant,
        );
        final bodyStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 14);

        Widget cell(Widget child, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: child,
          ),
        );

        Widget rowOf(
          TextStyle? style,
          Widget? leading,
          Widget name,
          Widget code,
          List<Widget> extras,
          Widget status,
          Widget actions, {
          required double minHeight,
        }) => DefaultTextStyle.merge(
          style: style,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (hasLeading)
                    SizedBox(
                      width: _leadingWidth,
                      child: leading ?? const SizedBox.shrink(),
                    ),
                  cell(name, 4),
                  cell(code, 2),
                  for (final (i, e) in extras.indexed)
                    cell(e, columns[shown[i]].flex),
                  SizedBox(
                    width: _statusWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: status,
                    ),
                  ),
                  if (actionCount > 0)
                    SizedBox(
                      width: actionCount * _actionWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        Text head(String t) => Text(t.toUpperCase(), maxLines: 1);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rowOf(
              headStyle,
              null,
              head(nameHeader),
              head(codeHeader),
              [for (final c in shown) head(columns[c].header)],
              head('Status'),
              const SizedBox.shrink(),
              minHeight: 36,
            ),
            for (final item in items) ...[
              const Divider(height: 1),
              InkWell(
                key: ValueKey(item.id),
                onTap: item.onTap,
                child: rowOf(
                  bodyStyle,
                  item.leading,
                  Row(
                    children: [
                      PersonAvatar(initials: item.initials),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _cellText(item.code),
                  [
                    for (final c in shown)
                      item.cells?[c] ?? _cellText(item.values[c]),
                  ],
                  item.statusBadge,
                  Row(mainAxisSize: MainAxisSize.min, children: item.actions),
                  minHeight: rowMinHeight,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// A value, or the muted "—" when the person genuinely has none.
  static Widget _cellText(String? value) => Builder(
    builder: (context) {
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      final empty = value == null || value.isEmpty;
      return Text(
        empty ? '—' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: empty ? TextStyle(color: muted) : null,
      );
    },
  );
}

/// A person on a phone: avatar, name, ID, a single line of detail, and the
/// status. The whole card is the tap target; row actions (the Login access
/// key) sit at the end.
class DirectoryCard extends StatelessWidget {
  final DirectoryRow item;

  const DirectoryCard({super.key, required this.item});

  /// Below this much row width (a 320px phone, or large text) the status pill
  /// moves under the name instead of squeezing the name beside it.
  static const double _narrow = 300;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = item.phoneLine;
    return InkWell(
      onTap: item.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final stacked = constraints.maxWidth < _narrow || scale > 1.3;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (item.leading != null) ...[
                    item.leading!,
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  PersonAvatar(initials: item.initials, size: 36),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 14,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          item.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            color: muted,
                          ),
                        ),
                        if (item.phoneDetail != null)
                          DefaultTextStyle.merge(
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: muted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            child: item.phoneDetail!,
                          )
                        else if (line != null && line.isNotEmpty)
                          Text(
                            line,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: muted,
                            ),
                          ),
                        if (stacked) ...[
                          const SizedBox(height: 4),
                          item.statusBadge,
                        ],
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: AppSpacing.sm),
                    item.statusBadge,
                  ],
                  ...item.actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
