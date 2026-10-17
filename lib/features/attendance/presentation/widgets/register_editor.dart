import 'package:flutter/material.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/attendance_calendar.dart';
import '../../domain/attendance_history_entry.dart';
import '../../domain/attendance_sheet.dart';
import 'attendance_sheet_rows.dart';
import 'attendance_summary_bar.dart';

/// What the editor hands back when the user saves.
class RegisterSubmit {
  final bool finalize;
  final String? reason;
  final CalendarDayKind dayKind;
  final String? overrideReason;

  const RegisterSubmit({
    required this.finalize,
    this.reason,
    required this.dayKind,
    this.overrideReason,
  });
}

/// The part of marking attendance that is identical for students and staff:
/// calendar banner and override, running totals, "mark all present", the
/// save / finalize flow with its confirmations (partial save, correction
/// reason, finalize), conflict handling, and the sheet itself. The pages only
/// choose *which* register to load and how to persist it.
///
/// Success is shown only after [onSubmit] has completed; a failure is shown
/// as a user-facing message and leaves the sheet untouched so nothing typed
/// is lost. [_saving] disables every action while a save is in flight, which
/// (with the deterministic ids and revision check underneath) is what stops
/// a double-click producing two writes.
class RegisterEditor extends StatefulWidget {
  final AttendanceSheet sheet;
  final String title;
  final String detailLabel;

  /// Null when the calendar is not known (still loading).
  final CalendarDayInfo? calendar;

  /// Why the chosen date cannot be used at all (future, outside the year).
  final String? dateError;

  /// May edit a not-yet-finalized register.
  final bool canMark;

  /// May correct a finalized register (with a reason) and override the calendar.
  final bool canManage;

  final Future<void> Function(RegisterSubmit submit) onSubmit;
  final Future<void> Function() onReload;
  final Future<List<AttendanceHistoryEntry>> Function(AttendanceEntry entry)?
  historyLoader;

  /// `subjectId -> label` for people on approved leave on this date. A
  /// display-only annotation from the leave module; see [AttendanceSheetRows].
  final Map<String, String> leaveLabels;

  const RegisterEditor({
    super.key,
    required this.sheet,
    required this.title,
    this.detailLabel = 'Roll',
    required this.calendar,
    this.dateError,
    required this.canMark,
    required this.canManage,
    required this.onSubmit,
    required this.onReload,
    this.historyLoader,
    this.leaveLabels = const {},
  });

  @override
  State<RegisterEditor> createState() => _RegisterEditorState();
}

class _RegisterEditorState extends State<RegisterEditor> {
  final _search = TextEditingController();
  final _overrideReason = TextEditingController();
  bool _saving = false;

  AttendanceSheet get sheet => widget.sheet;
  CalendarDayInfo? get calendar => widget.calendar;

  bool get _calendarBlocks =>
      calendar != null && calendar!.needsOverride && !widget.canManage;
  bool get _needsOverride =>
      calendar != null && calendar!.needsOverride && widget.canManage;

  /// Whether the status buttons are active at all.
  bool get _editable {
    if (_saving || widget.dateError != null || _calendarBlocks) return false;
    if (sheet.isFinalized) return widget.canManage;
    return widget.canMark;
  }

  @override
  void dispose() {
    _search.dispose();
    _overrideReason.dispose();
    super.dispose();
  }

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reason for correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This attendance is finalized. The change and your reason are recorded in its history.',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => controller.text.trim().isEmpty
                ? null
                : Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _submit({required bool finalize}) async {
    if (_saving) return;
    if (widget.dateError != null) {
      context.showSnackBar(widget.dateError!, isError: true);
      return;
    }
    if (_needsOverride && _overrideReason.text.trim().isEmpty) {
      context.showSnackBar(
        '${calendar!.description}. Enter a reason to record attendance on this day.',
        isError: true,
      );
      return;
    }

    String? reason;
    if (sheet.isFinalized) {
      reason = await _askReason();
      if (reason == null || !mounted) return;
    }

    if (finalize) {
      final problem = sheet.validateFinalize();
      if (problem != null) {
        context.showSnackBar(problem, isError: true);
        return;
      }
      if (!await _confirm(
            'Finalize attendance?',
            'Once finalized, only a manager can change it, and only with a written reason.',
            'Finalize',
          ) ||
          !mounted) {
        return;
      }
    } else {
      if (sheet.hasUnmarked) {
        final ok = await _confirm(
          'Save partial attendance?',
          '${sheet.tally.notMarked} of ${sheet.tally.total} are not marked. They will stay "not marked" — not present or absent.',
          'Save partial',
        );
        if (!ok || !mounted) return;
      }
      final problem = sheet.validateSave(
        allowPartial: true,
        reason: reason,
        canEditFinalized: widget.canManage,
      );
      if (problem != null) {
        context.showSnackBar(problem, isError: true);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        RegisterSubmit(
          finalize: finalize,
          reason: reason,
          dayKind: calendar?.kind ?? CalendarDayKind.workingDay,
          overrideReason: _needsOverride ? _overrideReason.text.trim() : null,
        ),
      );
      if (!mounted) return;
      context.showSnackBar(
        finalize
            ? 'Attendance finalized successfully.'
            : 'Attendance saved successfully.',
      );
      await widget.onReload();
    } on ConflictFailure catch (conflict) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Changed by someone else'),
          content: Text(
            '${conflict.message}\n\nNothing was saved. Your edits are discarded when you reload.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (mounted) await widget.onReload();
    } catch (error) {
      if (mounted) context.showSnackBar(userMessageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showHistory(AttendanceEntry entry) async {
    final loader = widget.historyLoader;
    if (loader == null) return;
    List<AttendanceHistoryEntry>? history;
    Object? failure;
    try {
      history = await loader(entry);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('History · ${entry.name}'),
        content: SizedBox(
          width: 420,
          child: failure != null
              ? Text(userMessageFor(failure))
              : history!.isEmpty
              ? const Text('No history yet.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final h in history.reversed)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${h.previousStatus?.displayName ?? 'Not marked'} → ${h.newStatus.displayName}',
                        ),
                        subtitle: Text(
                          [
                            if (h.changedAt != null) formatInstant(h.changedAt),
                            if ((h.reason ?? '').isNotEmpty)
                              'Reason: ${h.reason}',
                            if ((h.newRemarks ?? '').isNotEmpty)
                              'Remarks: ${h.newRemarks}',
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? sheet.entries
        : sheet.entries
              .where(
                (e) =>
                    e.name.toLowerCase().contains(query) ||
                    (e.detail ?? '').toLowerCase().contains(query),
              )
              .toList();
    final changeCount = sheet.changedEntries.length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: context.textStyles.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _banners(context),
                AttendanceSummaryBar(tally: sheet.tally, totalLabel: 'Total'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _editable && sheet.hasUnmarked
                          ? () => setState(sheet.markAllPresent)
                          : null,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Mark all present'),
                    ),
                    FilledButton.icon(
                      onPressed: _editable && sheet.isDirty && !_saving
                          ? () => _submit(finalize: false)
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        changeCount == 0
                            ? 'Save'
                            : 'Save ($changeCount change${changeCount == 1 ? '' : 's'})',
                      ),
                    ),
                    if (!sheet.isFinalized)
                      OutlinedButton.icon(
                        onPressed:
                            _editable && !_saving && sheet.entries.isNotEmpty
                            ? () => _submit(finalize: true)
                            : null,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Finalize'),
                      ),
                    TextButton.icon(
                      onPressed: _saving ? null : widget.onReload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reload'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  sheet.entries.isEmpty
                      ? 'Nobody is enrolled for this selection and date.'
                      : 'No match.',
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: AttendanceSheetRows(
              entries: visible,
              editable: _editable,
              detailLabel: widget.detailLabel,
              onChanged: () => setState(() {}),
              onShowHistory: widget.historyLoader == null ? null : _showHistory,
              leaveLabels: widget.leaveLabels,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  Widget _banners(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget banner(IconData icon, String text, {Color? color, Widget? extra}) {
      return Card(
        color: color,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text)),
                ],
              ),
              if (extra != null) extra,
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.dateError != null)
          banner(
            Icons.error_outline,
            widget.dateError!,
            color: scheme.errorContainer,
          ),
        if (calendar != null && widget.dateError == null)
          if (_calendarBlocks)
            banner(
              Icons.event_busy,
              '${calendar!.description}. Attendance cannot be marked on this day. A manager can override with a reason.',
              color: scheme.errorContainer,
            )
          else if (_needsOverride)
            banner(
              Icons.warning_amber_outlined,
              '${calendar!.description}. You can still record attendance as an authorized override — give a reason.',
              color: scheme.tertiaryContainer,
              extra: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: TextField(
                  controller: _overrideReason,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Override reason',
                    isDense: true,
                  ),
                ),
              ),
            )
          else if (calendar!.kind == CalendarDayKind.specialWorkingDay)
            banner(Icons.event_available, calendar!.description),
        if (sheet.isFinalized)
          banner(
            Icons.lock,
            widget.canManage
                ? 'Finalized. Any change needs a written reason and is recorded in the history.'
                : 'Finalized. Only a manager can correct this attendance.',
            color: scheme.secondaryContainer,
          ),
      ],
    );
  }
}
