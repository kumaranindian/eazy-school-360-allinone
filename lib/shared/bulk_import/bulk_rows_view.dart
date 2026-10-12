import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

import '../../core/theme/app_spacing.dart';
import '../../features/students/domain/bulk_student_import.dart'
    show BulkCellError;

enum BulkRowOutcome { imported, importedWithWarning, failed }

/// A fix typed or picked on the review screen. [line] null means "every row
/// whose cell currently equals [oldValue]".
class BulkCellEdit {
  final int? line;
  final String column;
  final String oldValue;
  final String newValue;

  const BulkCellEdit({
    this.line,
    required this.column,
    required this.oldValue,
    required this.newValue,
  });
}

typedef BulkCellEditHandler = Future<void> Function(BulkCellEdit edit);

/// Extra per-problem action (e.g. "Create department …"), or null.
typedef BulkExtraAction =
    Widget? Function(BulkRowView row, BulkCellError error);

/// One uploaded row as the review screen shows it — every row, valid or
/// not, in file order.
class BulkRowView {
  /// 1-based line in the file (header = line 1), same as the spreadsheet
  /// row number.
  final int line;

  /// "ADM-1 · Asha Kumar".
  final String who;

  /// Short description of what the row will create, e.g. "Class 1 · A".
  final String details;

  final List<BulkCellError> errors;

  /// Set after the import has run.
  final BulkRowOutcome? outcome;
  final String? outcomeMessage;

  const BulkRowView({
    required this.line,
    required this.who,
    required this.details,
    required this.errors,
    this.outcome,
    this.outcomeMessage,
  });

  bool get hasErrors => errors.isNotEmpty;
}

/// "A", "B", … "Z", "AA" for a zero-based column index.
String spreadsheetColumn(int index) {
  var n = index + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

enum _Filter { all, problems, ok }

/// Every row of the upload with its own problem list. Rows needing a fix
/// are expanded and numbered with exact steps; [header] (the file's
/// normalised column keys) lets each problem point at a spreadsheet cell
/// such as `M5`. After an import the same list shows each row's outcome.
class BulkRowsView extends StatefulWidget {
  final List<BulkRowView> rows;
  final List<String> header;

  /// When set, every problem gets an inline fix control; the handler
  /// updates the sheet data and re-validates.
  final BulkCellEditHandler? onEdit;
  final BulkExtraAction? extraAction;

  const BulkRowsView({
    super.key,
    required this.rows,
    required this.header,
    this.onEdit,
    this.extraAction,
  });

  @override
  State<BulkRowsView> createState() => _BulkRowsViewState();
}

class _BulkRowsViewState extends State<BulkRowsView> {
  _Filter _filter = _Filter.all;

  bool _isOk(BulkRowView r) =>
      r.outcome != null ? r.outcome != BulkRowOutcome.failed : !r.hasErrors;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final problems = rows.where((r) => !_isOk(r)).length;
    final ok = rows.length - problems;
    final shown = switch (_filter) {
      _Filter.all => rows,
      _Filter.problems => rows.where((r) => !_isOk(r)).toList(),
      _Filter.ok => rows.where(_isOk).toList(),
    };
    final afterImport = rows.any((r) => r.outcome != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: Text('All rows (${rows.length})'),
              selected: _filter == _Filter.all,
              onSelected: (_) => setState(() => _filter = _Filter.all),
            ),
            ChoiceChip(
              label: Text(
                '${afterImport ? 'Failed' : 'Needs fixing'} ($problems)',
              ),
              selected: _filter == _Filter.problems,
              onSelected: (_) => setState(() => _filter = _Filter.problems),
            ),
            ChoiceChip(
              label: Text('${afterImport ? 'Imported' : 'Ready'} ($ok)'),
              selected: _filter == _Filter.ok,
              onSelected: (_) => setState(() => _filter = _Filter.ok),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('No rows in this view.'),
          ),
        for (final r in shown)
          _RowCard(
            key: ValueKey('row-${r.line}'),
            row: r,
            header: widget.header,
            allRows: rows,
            onEdit: widget.onEdit,
            extraAction: widget.extraAction,
          ),
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  final BulkRowView row;
  final List<String> header;
  final List<BulkRowView> allRows;
  final BulkCellEditHandler? onEdit;
  final BulkExtraAction? extraAction;
  const _RowCard({
    super.key,
    required this.row,
    required this.header,
    required this.allRows,
    required this.onEdit,
    required this.extraAction,
  });

  String _cell(BulkCellError e) {
    final idx = header.indexOf(e.column);
    return idx < 0 ? '' : '${spreadsheetColumn(idx)}${row.line}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failedImport = row.outcome == BulkRowOutcome.failed;
    final warn = row.outcome == BulkRowOutcome.importedWithWarning;
    final bad = row.hasErrors || failedImport;

    final Color accent = bad
        ? scheme.error
        : warn
        ? AppColors.warning
        : AppColors.success;
    final IconData icon = bad
        ? Icons.error_outline
        : warn
        ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;
    final String status = switch (row.outcome) {
      BulkRowOutcome.imported => 'Imported',
      BulkRowOutcome.importedWithWarning => 'Imported — needs attention',
      BulkRowOutcome.failed => 'Not imported',
      null =>
        row.hasErrors
            ? '${row.errors.length} '
                  '${row.errors.length == 1 ? 'problem' : 'problems'} to fix'
            : 'Ready to import',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        color: bad
            ? scheme.errorContainer.withValues(alpha: 0.2)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Row ${row.line}'
                  '${row.who.isEmpty ? '' : ' · ${row.who}'}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(status, style: TextStyle(color: accent)),
            ],
          ),
          if (row.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(row.details, style: theme.textTheme.bodySmall),
            ),
          if (row.outcomeMessage != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(row.outcomeMessage!),
            ),
          if (row.hasErrors) ...[
            const SizedBox(height: AppSpacing.xs),
            for (var i = 0; i < row.errors.length; i++)
              _ErrorItem(
                key: ValueKey(
                  'err-${row.line}-${row.errors[i].column}-${row.errors[i].value}',
                ),
                number: i + 1,
                line: row.line,
                error: row.errors[i],
                cell: _cell(row.errors[i]),
                sameValueRows: allRows
                    .where(
                      (r) => r.errors.any(
                        (e) =>
                            e.column == row.errors[i].column &&
                            e.value == row.errors[i].value,
                      ),
                    )
                    .length,
                onEdit: onEdit,
                extra: extraAction?.call(row, row.errors[i]),
              ),
          ],
        ],
      ),
    );
  }
}

class _ErrorItem extends StatefulWidget {
  final int number;
  final int line;
  final BulkCellError error;
  final String cell;
  final int sameValueRows;
  final BulkCellEditHandler? onEdit;
  final Widget? extra;

  const _ErrorItem({
    super.key,
    required this.number,
    required this.line,
    required this.error,
    required this.cell,
    required this.sameValueRows,
    required this.onEdit,
    required this.extra,
  });

  @override
  State<_ErrorItem> createState() => _ErrorItemState();
}

class _ErrorItemState extends State<_ErrorItem> {
  late final TextEditingController _text = TextEditingController(
    text: widget.error.value,
  );
  String? _picked;
  bool _busy = false;

  bool get _usesChoices => widget.error.choices.isNotEmpty;

  String get _newValue => _usesChoices ? (_picked ?? '') : _text.text.trim();

  bool get _canApply =>
      !_busy &&
      (_usesChoices ? _picked != null : _newValue != widget.error.value.trim());

  Future<void> _apply({required bool all}) async {
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    setState(() => _busy = true);
    try {
      await onEdit(
        BulkCellEdit(
          line: all ? null : widget.line,
          column: widget.error.column,
          oldValue: widget.error.value,
          newValue: _newValue,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.error;
    final value = e.value.isEmpty ? '(empty)' : '"${e.value}"';
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.number}. ${e.label}'
            '${widget.cell.isEmpty ? '' : '  (cell ${widget.cell})'}',
            style: theme.textTheme.titleSmall,
          ),
          Text('You entered: $value'),
          Text("What's wrong: ${e.label} ${e.message}"),
          Text(
            'How to fix: ${e.fix}',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.onEdit != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: _usesChoices
                      ? DropdownButtonFormField<String>(
                          value: _picked,
                          isDense: true,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Correct ${e.label.toLowerCase()}',
                            isDense: true,
                          ),
                          items: [
                            for (final c in e.choices)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _picked = v),
                        )
                      : TextField(
                          controller: _text,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: 'Correct ${e.label.toLowerCase()}',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                ),
                FilledButton.tonal(
                  onPressed: _canApply ? () => _apply(all: false) : null,
                  child: const Text('Fix this row'),
                ),
                if (widget.sameValueRows > 1)
                  OutlinedButton(
                    onPressed: _canApply ? () => _apply(all: true) : null,
                    child: Text('Fix all ${widget.sameValueRows} rows'),
                  ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ?widget.extra,
              ],
            ),
          ],
        ],
      ),
    );
  }
}
