import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/attendance_sheet.dart';
import 'attendance_status_buttons.dart';

/// The entries of an [AttendanceSheet] as a sliver: a table-like row per
/// person on tablet/desktop (detail · name · P/A/L/H · inline remarks), a
/// compact card with full-width buttons on mobile. All behaviour lives in
/// the sheet; this only renders and forwards taps.
class AttendanceSheetRows extends StatelessWidget {
  final List<AttendanceEntry> entries;
  final bool editable;
  final VoidCallback onChanged;
  final void Function(AttendanceEntry entry)? onShowHistory;
  final String detailLabel;

  /// `subjectId -> label` for people on approved leave that day (from the
  /// leave module). Display only: it never changes a status, a remark or
  /// what is saved — attendance and leave stay separate records.
  final Map<String, String> leaveLabels;

  const AttendanceSheetRows({
    super.key,
    required this.entries,
    required this.editable,
    required this.onChanged,
    this.onShowHistory,
    this.detailLabel = 'Roll',
    this.leaveLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // The table-style row needs ~880px (detail + name + 4 buttons +
        // remarks + actions); anything narrower — phones and tablets once the
        // navigation rail has taken its share — gets the compact card.
        final mobile = constraints.crossAxisExtent < 880;
        return SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: mobile ? AppSpacing.sm : 0),
          itemBuilder: (context, index) => mobile
              ? _MobileCard(
                  entry: entries[index],
                  editable: editable,
                  onChanged: onChanged,
                  onShowHistory: onShowHistory,
                  leaveLabel: leaveLabels[entries[index].subjectId],
                )
              : _DesktopRow(
                  entry: entries[index],
                  editable: editable,
                  onChanged: onChanged,
                  onShowHistory: onShowHistory,
                  leaveLabel: leaveLabels[entries[index].subjectId],
                ),
        );
      },
    );
  }
}

Future<void> _editRemarks(
  BuildContext context,
  AttendanceEntry entry,
  VoidCallback onChanged,
) async {
  final controller = TextEditingController(text: entry.remarks);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remarks · ${entry.name}'),
      content: TextField(
        controller: controller,
        maxLength: 200,
        maxLines: 2,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Remarks (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result != null) {
    entry.remarks = result;
    onChanged();
  }
}

class _EntryActions extends StatelessWidget {
  final AttendanceEntry entry;
  final bool editable;
  final VoidCallback onChanged;
  final void Function(AttendanceEntry entry)? onShowHistory;

  const _EntryActions({
    required this.entry,
    required this.editable,
    required this.onChanged,
    this.onShowHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Remarks',
          icon: Icon(
            (entry.remarks ?? '').trim().isEmpty
                ? Icons.comment_outlined
                : Icons.comment,
          ),
          onPressed: editable
              ? () => _editRemarks(context, entry, onChanged)
              : null,
        ),
        IconButton(
          tooltip: 'Reset to saved',
          icon: const Icon(Icons.restart_alt),
          onPressed: editable && entry.isChanged
              ? () {
                  entry.status = entry.savedStatus;
                  entry.remarks = entry.savedRemarks;
                  onChanged();
                }
              : null,
        ),
        if (onShowHistory != null && entry.isSaved)
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => onShowHistory!(entry),
          ),
      ],
    );
  }
}

/// "On approved leave" beside a name. Display only.
class _LeaveChip extends StatelessWidget {
  final String label;

  const _LeaveChip(this.label);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.beach_access_outlined,
              size: 14,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopRow extends StatelessWidget {
  final AttendanceEntry entry;
  final bool editable;
  final VoidCallback onChanged;
  final void Function(AttendanceEntry entry)? onShowHistory;
  final String? leaveLabel;

  const _DesktopRow({
    required this.entry,
    required this.editable,
    required this.onChanged,
    this.onShowHistory,
    this.leaveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: entry.isChanged
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.25)
            : null,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              entry.detail ?? '—',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(entry.name, overflow: TextOverflow.ellipsis),
                ),
                if (leaveLabel != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _LeaveChip(leaveLabel!),
                    ),
                  ),
                if (entry.status == null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Not marked',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          AttendanceStatusButtons(
            selected: entry.status,
            enabled: editable,
            onSelected: (s) {
              entry.status = s;
              onChanged();
            },
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 180,
            child: Text(
              (entry.remarks ?? '').trim().isEmpty ? '' : entry.remarks!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _EntryActions(
            entry: entry,
            editable: editable,
            onChanged: onChanged,
            onShowHistory: onShowHistory,
          ),
        ],
      ),
    );
  }
}

class _MobileCard extends StatelessWidget {
  final AttendanceEntry entry;
  final bool editable;
  final VoidCallback onChanged;
  final void Function(AttendanceEntry entry)? onShowHistory;
  final String? leaveLabel;

  const _MobileCard({
    required this.entry,
    required this.editable,
    required this.onChanged,
    this.onShowHistory,
    this.leaveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: entry.isChanged
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.25)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (entry.detail != null) entry.detail!,
                      entry.name,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _EntryActions(
                  entry: entry,
                  editable: editable,
                  onChanged: onChanged,
                  onShowHistory: onShowHistory,
                ),
              ],
            ),
            if (leaveLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _LeaveChip(leaveLabel!),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AttendanceStatusButtons(
                selected: entry.status,
                enabled: editable,
                expanded: true,
                onSelected: (s) {
                  entry.status = s;
                  onChanged();
                },
              ),
            ),
            if ((entry.remarks ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.remarks!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
