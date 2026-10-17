import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/staff_status.dart';
import 'staff_status_chip.dart';

/// One teacher as the list shows them. The page builds these from its own
/// rows (display names already resolved); the widgets below only lay them out.
class TeacherListItem {
  final String staffId;
  final String name;
  final String employeeCode;

  /// Class-and-section names, comma separated; null when the teacher has no
  /// active assignment (shown as "—" in the table, omitted on a phone).
  final String? classes;
  final String? subjects;
  final String? classTeacherOf;
  final StaffStatus status;
  final VoidCallback onTap;

  const TeacherListItem({
    required this.staffId,
    required this.name,
    required this.employeeCode,
    required this.classes,
    required this.subjects,
    required this.classTeacherOf,
    required this.status,
    required this.onTap,
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

/// The teacher list card: the table (tablet / desktop) or compact cards
/// (phone), and the "Showing N of TOTAL / Load more" footer, all in one card.
///
/// Paging stays with the page: it passes the count, whether there is more,
/// whether a load is running, and the callback — nothing here fetches.
class TeacherListCard extends StatelessWidget {
  final List<TeacherListItem> items;
  final ScreenSize layout;
  final Widget emptyState;

  /// The total the shown teachers are part of, when the page knows it (it does
  /// not while a search or assignment filter has taken over the query).
  final int? total;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;

  const TeacherListCard({
    super.key,
    required this.items,
    required this.layout,
    required this.emptyState,
    required this.total,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
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
                TeacherCard(key: ValueKey(items[i].staffId), item: items[i]),
              ]
            else
              TeacherTable(items: items),
            if (items.isNotEmpty) ...[
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

/// A teacher's circle of initials.
class TeacherAvatar extends StatelessWidget {
  final String initials;
  final double size;

  const TeacherAvatar({super.key, required this.initials, this.size = 30});

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

/// Desktop / tablet rows. Columns are dropped by the width the table really
/// has — "Class teacher" first, then "Subjects" — never by the device; the
/// dropped details stay one tap away on the teacher's profile.
class TeacherTable extends StatelessWidget {
  final List<TeacherListItem> items;

  const TeacherTable({super.key, required this.items});

  static const double rowMinHeight = 46;
  static const double _statusWidth = 112;
  static const double _showClassTeacherAt = 900;
  static const double _showSubjectsAt = 700;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final classTeacher = width >= _showClassTeacherAt;
        final subjects = width >= _showSubjectsAt;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TableRow(
              header: true,
              classTeacher: classTeacher,
              subjects: subjects,
              cells: const _Cells(
                teacher: Text('Teacher'),
                id: Text('ID'),
                classes: Text('Classes'),
                subjects: Text('Subjects'),
                classTeacher: Text('Class teacher'),
                status: Text('Status'),
              ),
            ),
            for (final item in items) ...[
              const Divider(height: 1),
              _TableRow(
                key: ValueKey(item.staffId),
                header: false,
                classTeacher: classTeacher,
                subjects: subjects,
                onTap: item.onTap,
                cells: _Cells(
                  teacher: Row(
                    children: [
                      TeacherAvatar(initials: item.initials),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  id: _cellText(item.employeeCode),
                  classes: _cellText(item.classes),
                  subjects: _cellText(item.subjects),
                  classTeacher: _cellText(item.classTeacherOf),
                  status: Align(
                    alignment: Alignment.centerRight,
                    child: StaffStatusChip(status: item.status, dense: true),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// A value, or the muted "—" when the teacher genuinely has none.
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

class _Cells {
  final Widget teacher;
  final Widget id;
  final Widget classes;
  final Widget subjects;
  final Widget classTeacher;
  final Widget status;

  const _Cells({
    required this.teacher,
    required this.id,
    required this.classes,
    required this.subjects,
    required this.classTeacher,
    required this.status,
  });
}

class _TableRow extends StatelessWidget {
  final bool header;
  final bool classTeacher;
  final bool subjects;
  final _Cells cells;
  final VoidCallback? onTap;

  const _TableRow({
    super.key,
    required this.header,
    required this.classTeacher,
    required this.subjects,
    required this.cells,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = header
        ? theme.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyMedium?.copyWith(fontSize: 14);
    Widget cell(Widget child, int flex) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: child,
      ),
    );
    final row = DefaultTextStyle.merge(
      style: style,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: header ? 36 : TeacherTable.rowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              cell(header ? _upper(cells.teacher) : cells.teacher, 4),
              cell(header ? _upper(cells.id) : cells.id, 2),
              cell(header ? _upper(cells.classes) : cells.classes, 3),
              if (subjects)
                cell(header ? _upper(cells.subjects) : cells.subjects, 3),
              if (classTeacher)
                cell(
                  header ? _upper(cells.classTeacher) : cells.classTeacher,
                  2,
                ),
              SizedBox(
                width: TeacherTable._statusWidth,
                child: header
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: _upper(cells.status),
                      )
                    : cells.status,
              ),
            ],
          ),
        ),
      ),
    );
    if (header || onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _upper(Widget w) =>
      w is Text ? Text(w.data!.toUpperCase(), maxLines: 1) : w;
}

/// A teacher on a phone: avatar, name, ID, a single line of what they teach,
/// and the status. The whole card is the tap target.
class TeacherCard extends StatelessWidget {
  final TeacherListItem item;

  const TeacherCard({super.key, required this.item});

  /// "Class 3 - A · Maths" - only the parts that exist, no empty separators;
  /// null when there is nothing to say (the line is then not drawn at all).
  String? get meta {
    final parts = [
      item.classes,
      item.subjects,
      if (item.classTeacherOf != null) 'Class teacher: ${item.classTeacherOf}',
    ].whereType<String>().where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = meta;
    return InkWell(
      onTap: item.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TeacherAvatar(initials: item.initials, size: 36),
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
                      item.employeeCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: muted,
                      ),
                    ),
                    if (line != null)
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StaffStatusChip(status: item.status, dense: true),
            ],
          ),
        ),
      ),
    );
  }
}
