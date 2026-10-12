import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:printing/printing.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../domain/exam_enums.dart';
import '../../domain/result_calculator.dart';
import 'report_card_pdf.dart';

String fmtNum(double? v, {int decimals = 2}) {
  if (v == null) return '–';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(decimals).replaceFirst(RegExp(r'0+$'), '');
}

class ExamStatusPill extends StatelessWidget {
  final ExamStatus status;
  const ExamStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (status) {
      ExamStatus.draft => (null, Icons.edit_outlined),
      ExamStatus.scheduled => (scheme.primary, Icons.event_available),
      ExamStatus.inProgress => (scheme.tertiary, Icons.edit_note),
      ExamStatus.completed => (scheme.secondary, Icons.fact_check_outlined),
      ExamStatus.published => (AppColors.success, Icons.public),
      ExamStatus.withdrawn => (scheme.error, Icons.undo),
      ExamStatus.cancelled => (scheme.outline, Icons.block),
    };
    return StatusPill(label: status.displayName, color: color, icon: icon);
  }
}

class SheetStatusPill extends StatelessWidget {
  final SheetStatus? status;
  const SheetStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status == null) {
      return StatusPill(
        label: 'Not started',
        color: scheme.outline,
        icon: Icons.radio_button_unchecked,
      );
    }
    return switch (status!) {
      SheetStatus.draft => StatusPill(
        label: 'Draft',
        icon: Icons.edit_outlined,
      ),
      SheetStatus.submitted => StatusPill(
        label: 'Awaiting review',
        color: scheme.tertiary,
        icon: Icons.hourglass_top,
      ),
      SheetStatus.approved => StatusPill(
        label: 'Approved',
        color: AppColors.success,
        icon: Icons.check_circle_outline,
      ),
      SheetStatus.returned => StatusPill(
        label: 'Returned',
        color: scheme.error,
        icon: Icons.undo,
      ),
    };
  }
}

class OverallPill extends StatelessWidget {
  final OverallResult result;
  const OverallPill(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (result) {
      OverallResult.pass => StatusPill(
        label: 'Pass',
        color: AppColors.success,
        icon: Icons.check,
      ),
      OverallResult.fail => StatusPill(
        label: 'Fail',
        color: scheme.error,
        icon: Icons.close,
      ),
      OverallResult.notApplicable => StatusPill(
        label: 'Not applicable',
        color: scheme.outline,
      ),
    };
  }
}

/// A one-line reason for the user when asking for a free-text reason.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final t = controller.text.trim();
            if (t.length < 3) return;
            Navigator.of(ctx).pop(t);
          },
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The subject table of one result (screen version of the report card).
class ResultTable extends StatelessWidget {
  final StudentResult result;

  const ResultTable({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasComponents = result.lines.any((l) => l.theory != null);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 52,
        columns: [
          const DataColumn(label: Text('Subject')),
          if (hasComponents)
            const DataColumn(label: Text('Theory'), numeric: true),
          if (hasComponents)
            const DataColumn(label: Text('Practical'), numeric: true),
          const DataColumn(label: Text('Max'), numeric: true),
          const DataColumn(label: Text('Obtained'), numeric: true),
          const DataColumn(label: Text('%'), numeric: true),
          const DataColumn(label: Text('Grade')),
          const DataColumn(label: Text('Result')),
        ],
        rows: [
          for (final l in result.lines)
            DataRow(
              cells: [
                DataCell(Text(l.subjectName)),
                if (hasComponents) DataCell(Text(fmtNum(l.theory))),
                if (hasComponents) DataCell(Text(fmtNum(l.practical))),
                DataCell(Text(fmtNum(l.maxMarks))),
                DataCell(
                  Text(
                    l.outcome == SubjectOutcome.absent ||
                            l.outcome == SubjectOutcome.exempted ||
                            l.outcome == SubjectOutcome.pending
                        ? ReportCardPdf.outcomeLabel(l.outcome)
                        : fmtNum(l.obtained),
                  ),
                ),
                DataCell(Text(fmtNum(l.percent))),
                DataCell(Text(l.grade ?? '–')),
                DataCell(
                  Text(
                    ReportCardPdf.outcomeLabel(l.outcome),
                    style: l.outcome == SubjectOutcome.failed
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Totals, grade, result and rank of one student.
class ResultTotals extends StatelessWidget {
  final StudentResult result;
  final bool showRank;

  const ResultTotals({super.key, required this.result, this.showRank = true});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        CountTileText(
          label: 'Total',
          value: result.totalMax == 0
              ? '–'
              : '${fmtNum(result.totalObtained)} / ${fmtNum(result.totalMax)}',
        ),
        CountTileText(
          label: 'Percentage',
          value: result.overallPercentage == null
              ? '–'
              : '${fmtNum(result.overallPercentage)}%',
        ),
        CountTileText(label: 'Grade', value: result.overallGrade ?? '–'),
        if (result.gpa != null)
          CountTileText(label: 'GPA', value: fmtNum(result.gpa)),
        if (showRank && result.rank != null)
          CountTileText(
            label: 'Rank',
            value: '${result.rank} of ${result.classSize}',
          ),
        SizedBox(
          width: 150,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Result', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  OverallPill(result.result),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CountTileText extends StatelessWidget {
  final String label;
  final String value;

  const CountTileText({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A report card on screen with print and download actions. The PDF is built
/// on the device from the stored result; there is no public URL.
class ReportCardPanel extends StatefulWidget {
  final ReportCardData data;

  const ReportCardPanel({super.key, required this.data});

  @override
  State<ReportCardPanel> createState() => _ReportCardPanelState();
}

class _ReportCardPanelState extends State<ReportCardPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function(List<int> bytes) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ReportCardPdf.build(widget.data);
      await action(bytes);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final r = d.summary.result;
    final fileName =
        'report-card-${r.studentName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}'
        '-${d.summary.examName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.pdf';
    return SectionCard(
      title: 'Report card',
      actions: [
        if (_busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.schoolName, style: Theme.of(context).textTheme.titleLarge),
          Text('${d.summary.examName} · ${d.academicYearName}'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${r.studentName}'
            '${r.admissionNumber == null ? '' : ' · Adm. ${r.admissionNumber}'}'
            ' · ${d.className} – ${d.sectionName}',
          ),
          if (d.provisional)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Provisional — not a published result.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          ResultTable(result: r),
          const SizedBox(height: AppSpacing.md),
          ResultTotals(result: r),
          if (d.summary.attendance != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Attendance: ${d.summary.attendance!.percentage == null ? 'none recorded' : '${fmtNum(d.summary.attendance!.percentage, decimals: 1)}%'}'
              ' (${fmtNum(d.summary.attendance!.attendedDays)} of '
              '${d.summary.attendance!.markedDays} marked days, '
              '${d.summary.attendance!.fromKey} to ${d.summary.attendance!.toKey})',
            ),
          ],
          if (d.summary.teacherRemark.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Class teacher: ${d.summary.teacherRemark}'),
          ],
          if (d.summary.principalRemark.isNotEmpty)
            Text('Principal: ${d.summary.principalRemark}'),
          const SizedBox(height: AppSpacing.md),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (bytes) => Printing.layoutPdf(
                          name: fileName,
                          onLayout: (_) async => Uint8List.fromList(bytes),
                        ),
                      ),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (bytes) => Printing.sharePdf(
                          bytes: Uint8List.fromList(bytes),
                          filename: fileName,
                        ),
                      ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
