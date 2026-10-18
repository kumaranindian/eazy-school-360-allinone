import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_csv.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_summary.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';

/// `/fees/reports` — collections for a date range (by payment method, with
/// reversals and refunds beside them), outstanding balance by class and
/// section, and a way into any student's ledger.
///
/// Definitions: *collected* counts ACTIVE payments dated in the range — a
/// reversed payment is excluded; *reversed* / *refunded* are the reversal
/// records dated in the range; *outstanding* is the balance of open
/// (issued / partially paid) invoices — void invoices are excluded.
class FeeReportsPage extends StatelessWidget {
  const FeeReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fee reports')),
      body: FeeScope(builder: (context, fee) => _Reports(fee: fee)),
    );
  }
}

class _Reports extends ConsumerStatefulWidget {
  final FeeContext fee;

  const _Reports({required this.fee});

  @override
  ConsumerState<_Reports> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<_Reports> {
  late String _from = FeeDates.todayKey(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
  );
  late String _to = FeeDates.todayKey();
  CollectionSummary? _collections;
  List<SectionOutstanding>? _sections;
  bool _loadingCollections = false;
  bool _loadingSections = false;
  String? _error;

  Future<void> _loadCollections() async {
    if (_from.compareTo(_to) > 0) {
      context.showSnackBar(
        'The start date is after the end date.',
        isError: true,
      );
      return;
    }
    setState(() {
      _loadingCollections = true;
      _error = null;
    });
    try {
      final fee = widget.fee;
      final result = await ref
          .read(feeReportRepositoryProvider)
          .loadCollections(
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            academicYearId: fee.year.academicYearId,
            fromKey: _from,
            toKey: _to,
          );
      if (mounted) setState(() => _collections = result);
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingCollections = false);
    }
  }

  Future<void> _loadSections() async {
    final fee = widget.fee;
    setState(() {
      _loadingSections = true;
      _error = null;
    });
    try {
      final classes = (await ref.read(
        classesProvider(fee.yearKey).future,
      )).where((c) => c.status.wireValue == 'ACTIVE').toList();
      final jobs = <Future<SectionOutstanding>>[];
      for (final SchoolClass c in classes) {
        final List<Section> sections = (await ref.read(
          sectionsProvider((
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            academicYearId: fee.year.academicYearId,
            classId: c.classId,
          )).future,
        )).where((s) => s.status.wireValue == 'ACTIVE').toList();
        for (final s in sections) {
          jobs.add(
            ref
                .read(feeReportRepositoryProvider)
                .loadSectionOutstanding(
                  schoolId: fee.schoolId,
                  branchId: fee.branchId,
                  academicYearId: fee.year.academicYearId,
                  classId: c.classId,
                  className: c.name,
                  sectionId: s.sectionId,
                  sectionName: s.name,
                ),
          );
        }
      }
      final result = await Future.wait(jobs);
      if (mounted) setState(() => _sections = result);
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingSections = false);
    }
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked != null) {
      setState(
        () => from
            ? _from = FeeDates.todayKey(picked)
            : _to = FeeDates.todayKey(picked),
      );
    }
  }

  Future<void> _findStudent() async {
    final fee = widget.fee;
    final controller = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          return _StudentSearch(
            controller: controller,
            schoolId: fee.schoolId,
            branchId: fee.branchId,
          );
        },
      ),
    );
    controller.dispose();
    if (picked != null && mounted) {
      context.push('/fees/invoices?studentId=$picked');
    }
  }

  String _csvCollections(CollectionSummary c) => AttendanceCsv.encode(
    ['Measure', 'Amount', 'Count'],
    [
      [
        'Collected (active payments)',
        Money.plain(c.collectedMinor, currency: widget.fee.currency),
        c.paymentCount,
      ],
      for (final e in c.byMethodMinor.entries)
        [
          '  ${PaymentMethod.fromWireValue(e.key).displayName}',
          Money.plain(e.value, currency: widget.fee.currency),
          '',
        ],
      [
        'Reversed',
        Money.plain(c.reversedMinor, currency: widget.fee.currency),
        '',
      ],
      [
        'Refunded',
        Money.plain(c.refundedMinor, currency: widget.fee.currency),
        '',
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final c = fee.currency;
    final text = context.textStyles;
    final collections = _collections;
    final sections = _sections;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Collections', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => _pick(true),
              child: Text('From ${FeeDates.display(_from)}'),
            ),
            OutlinedButton(
              onPressed: () => _pick(false),
              child: Text('To ${FeeDates.display(_to)}'),
            ),
            FilledButton.icon(
              onPressed: _loadingCollections ? null : _loadCollections,
              icon: _loadingCollections
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assessment_outlined),
              label: const Text('Run'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(_error!, style: TextStyle(color: context.colors.error)),
          ),
        if (collections != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${Money.format(collections.collectedMinor, currency: c)} collected in ${collections.paymentCount} payments',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (collections.byMethodMinor.isEmpty)
                    const Text('No payments in this period.'),
                  for (final e in collections.byMethodMinor.entries)
                    Text(
                      '${PaymentMethod.fromWireValue(e.key).displayName}: ${Money.format(e.value, currency: c)}',
                    ),
                  const Divider(),
                  Text(
                    'Reversed in period: ${Money.format(collections.reversedMinor, currency: c)}',
                  ),
                  Text(
                    'Refunded in period: ${Money.format(collections.refundedMinor, currency: c)}',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Reversed payments are excluded from "collected".',
                    style: text.bodySmall,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _csvCollections(collections)),
                        );
                        if (context.mounted) {
                          context.showSnackBar('Report copied as CSV.');
                        }
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy CSV'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Outstanding by class and section', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _loadingSections ? null : _loadSections,
          icon: _loadingSections
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_chart_outlined),
          label: const Text('Run'),
        ),
        if (sections != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                for (final s in sections)
                  ListTile(
                    dense: true,
                    title: Text('${s.className} ${s.sectionName}'),
                    subtitle: Text('${s.invoiceCount} open invoices'),
                    trailing: Text(
                      Money.format(s.outstandingMinor, currency: c),
                    ),
                  ),
                ListTile(
                  title: Text('Total', style: text.titleSmall),
                  trailing: Text(
                    Money.format(
                      sections.fold(0, (a, s) => a + s.outstandingMinor),
                      currency: c,
                    ),
                    style: text.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final csv = AttendanceCsv.encode(
                  ['Class', 'Section', 'Open invoices', 'Outstanding'],
                  [
                    for (final s in sections)
                      [
                        s.className,
                        s.sectionName,
                        s.invoiceCount,
                        Money.plain(s.outstandingMinor, currency: c),
                      ],
                  ],
                );
                await Clipboard.setData(ClipboardData(text: csv));
                if (context.mounted) {
                  context.showSnackBar('Report copied as CSV.');
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy CSV'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Student ledger', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _findStudent,
          icon: const Icon(Icons.person_search_outlined),
          label: const Text('Find a student'),
        ),
      ],
    );
  }
}

class _StudentSearch extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String schoolId;
  final String branchId;

  const _StudentSearch({
    required this.controller,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_StudentSearch> createState() => _StudentSearchState();
}

class _StudentSearchState extends ConsumerState<_StudentSearch> {
  List<({String id, String name, String admission})> _results = const [];
  String? _error;
  bool _busy = false;

  Future<void> _search() async {
    if (widget.controller.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(studentRepositoryProvider)
          .searchStudentsByName(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            query: widget.controller.text,
          );
      if (mounted) {
        setState(
          () => _results = [
            for (final s in page.items)
              (
                id: s.studentId,
                name: s.displayName,
                admission: s.admissionNumber,
              ),
          ],
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find a student'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name starts with…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(_error!),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _results)
                    ListTile(
                      dense: true,
                      title: Text(r.name),
                      subtitle: Text(r.admission),
                      onTap: () => Navigator.of(context).pop(r.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
