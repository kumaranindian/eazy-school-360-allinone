import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/expense.dart';
import '../../domain/expense_report.dart';
import '../providers/expense_providers.dart';
import '../../../../shared/dates/school_date_picker.dart';

/// Saves CSV text for the person (a save dialog). Behind a provider so tests
/// need no platform dialog. Returns whether a file was saved.
abstract class CsvSaver {
  Future<bool> save(String fileName, String content);
}

class FilePickerCsvSaver implements CsvSaver {
  const FilePickerCsvSaver();

  @override
  Future<bool> save(String fileName, String content) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    return saved != null;
  }
}

final expenseCsvSaverProvider = Provider<CsvSaver>(
  (ref) => const FilePickerCsvSaver(),
);

enum _Preset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last30('Last 30 days'),
  thisYear('This year'),
  custom('Custom');

  final String label;
  const _Preset(this.label);
}

/// `/expenses/reports`: what the school spent, by category, month and branch,
/// and a CSV of the same rows. Spend means approved plus paid.
class ExpenseReportsPage extends StatelessWidget {
  const ExpenseReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expense reports')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _Report(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
          canSeeWholeSchool: tenant.role == UserRole.schoolAdmin,
        ),
      ),
    );
  }
}

class _Report extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final bool canSeeWholeSchool;

  const _Report({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.canSeeWholeSchool,
  });

  @override
  ConsumerState<_Report> createState() => _ReportState();
}

class _ReportState extends ConsumerState<_Report> {
  _Preset _preset = _Preset.thisMonth;
  late String _from;
  late String _to;
  bool _all = false;
  bool _exporting = false;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _apply(_Preset.thisMonth);
  }

  void _apply(_Preset p) {
    final today = SchoolTime.today();
    final r = switch (p) {
      _Preset.thisMonth => ExpenseRanges.thisMonth(today),
      _Preset.lastMonth => ExpenseRanges.lastMonth(today),
      _Preset.last30 => ExpenseRanges.last30Days(today),
      _Preset.thisYear => ExpenseRanges.thisYear(today),
      _Preset.custom => (from: _from, to: _to),
    };
    _preset = p;
    _from = r.from;
    _to = r.to;
    _rangeError = null;
  }

  Future<void> _pick(bool from) async {
    final today = SchoolTime.today();
    final current = DateTime.tryParse(from ? _from : _to) ?? today;
    final picked = await showSchoolDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(today.year - 5, today.month, today.day),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _preset = _Preset.custom;
      if (from) {
        _from = SchoolTime.keyOf(picked);
      } else {
        _to = SchoolTime.keyOf(picked);
      }
      _rangeError = ExpenseRanges.problem(_from, _to, SchoolTime.todayKey());
    });
  }

  ExpenseReportKey get _key => (
    schoolId: widget.schoolId,
    branchId: _all ? null : widget.branchId,
    fromDate: _from,
    toDate: _to,
  );

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final out = await ref
          .read(expenseRepositoryProvider)
          .exportCsv(
            widget.schoolId,
            branchId: _key.branchId,
            fromDate: _from,
            toDate: _to,
          );
      final saved = await ref
          .read(expenseCsvSaverProvider)
          .save('expenses_${_from}_to_$_to.csv', out.csv);
      if (!mounted) return;
      final msg = !saved
          ? 'Nothing was saved.'
          : out.capped
          ? 'Saved ${out.rows} rows (the maximum). Choose a shorter range for the rest.'
          : 'Saved ${out.rows} rows.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _rangeError == null;
    final report = valid ? ref.watch(expenseReportProvider(_key)) : null;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final p in _Preset.values)
              ChoiceChip(
                key: ValueKey('range-${p.name}'),
                label: Text(p.label),
                selected: _preset == p,
                onSelected: (_) => setState(() => _apply(p)),
              ),
          ],
        ),
        if (_preset == _Preset.custom)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  key: const ValueKey('range-from'),
                  onPressed: () => _pick(true),
                  child: Text('From ${SchoolTime.formatKey(_from)}'),
                ),
                OutlinedButton(
                  key: const ValueKey('range-to'),
                  onPressed: () => _pick(false),
                  child: Text('To ${SchoolTime.formatKey(_to)}'),
                ),
              ],
            ),
          ),
        if (_rangeError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _rangeError!,
              key: const ValueKey('range-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.canSeeWholeSchool)
          SwitchListTile(
            key: const ValueKey('report-all-branches'),
            contentPadding: EdgeInsets.zero,
            title: const Text('All branches'),
            value: _all,
            onChanged: (v) => setState(() => _all = v),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (report != null)
          report.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(expenseReportProvider(_key)),
            ),
            data: (r) => _Body(
              report: r,
              exporting: _exporting,
              onExport: _exporting ? null : _export,
            ),
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  final ExpenseReport report;
  final bool exporting;
  final VoidCallback? onExport;

  const _Body({
    required this.report,
    required this.exporting,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String money(int minor) => Money.format(minor, currency: report.currency);
    if (report.isEmpty) {
      return const EmptyView(
        icon: Icons.insights_outlined,
        message: 'No expenses in this period.',
      );
    }
    final t = report.totals;
    Widget card(String key, String label, int minor) => SizedBox(
      width: 220,
      child: Card(
        key: ValueKey(key),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelMedium),
              const SizedBox(height: 4),
              Text(money(minor), style: text.titleLarge),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.truncated)
          Card(
            key: const ValueKey('report-truncated'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'This period holds more expenses than one report reads, so '
                'the numbers cover only part of it. Choose a shorter period.',
              ),
            ),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            card('report-spent', 'Spent (approved + paid)', t.spentMinor),
            card('report-paid', 'Paid', t.paidMinor),
            card(
              'report-unpaid',
              'Approved, not yet paid',
              t.unpaidApprovedMinor,
            ),
            card(
              'report-awaiting',
              'Awaiting approval',
              t.awaitingApprovalMinor,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in ExpenseStatus.values)
              if ((report.byStatus[s]?.count ?? 0) > 0)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${s.label}: ${report.byStatus[s]!.count}'),
                ),
          ],
        ),
        _Breakdown(
          key: const ValueKey('report-by-category'),
          title: 'By category',
          rows: report.byCategory,
          money: money,
        ),
        _Breakdown(
          key: const ValueKey('report-by-month'),
          title: 'By month',
          rows: report.byMonth,
          money: money,
        ),
        if (report.wholeSchool)
          _Breakdown(
            key: const ValueKey('report-by-branch'),
            title: 'By branch',
            rows: report.byBranch,
            money: money,
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Spend counts approved and paid expenses only. Drafts, expenses '
          'awaiting approval, rejected and cancelled ones are not included.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('report-export'),
            onPressed: onExport,
            icon: const Icon(Icons.download_outlined),
            label: Text(exporting ? 'Preparing…' : 'Export CSV'),
          ),
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  final String title;
  final List<ExpenseBucket> rows;
  final String Function(int) money;

  const _Breakdown({
    super.key,
    required this.title,
    required this.rows,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final biggest = rows
        .map((r) => r.totalMinor)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                key: ValueKey('${title.toLowerCase()}-${r.key}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(money(r.totalMinor), style: text.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: r.totalMinor / biggest),
                  Text(
                    '${r.count} expense${r.count == 1 ? '' : 's'} · '
                    '${money(r.paidMinor)} paid',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
