import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';
import '../widgets/student_all_years_ledger.dart';
import '../widgets/fee_widgets.dart';

enum _StatusFilter { all, overdue, issued, partiallyPaid, paid, voided }

/// `/fees/invoices` — invoices of the chosen year, filtered by class,
/// section, status (including a derived "Overdue"), due-date range, or
/// searched by invoice number; cursor-paginated. `?studentId=` opens a
/// student's invoices (their ledger).
class InvoicesPage extends StatelessWidget {
  final String? studentId;

  const InvoicesPage({super.key, this.studentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(studentId == null ? 'Invoices' : 'Student invoices'),
      ),
      body: FeeScope(
        builder: (context, fee) => _Invoices(fee: fee, studentId: studentId),
      ),
    );
  }
}

class _Invoices extends ConsumerStatefulWidget {
  final FeeContext fee;
  final String? studentId;

  const _Invoices({required this.fee, this.studentId});

  @override
  ConsumerState<_Invoices> createState() => _InvoicesState();
}

class _InvoicesState extends ConsumerState<_Invoices> {
  final _controller = PagedListController<Invoice>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _classId;
  String? _sectionId;
  _StatusFilter _status = _StatusFilter.all;
  Future<List<Invoice>>? _ledger;
  Future<List<Invoice>>? _allYears;
  String? _from;
  String? _to;

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.studentId != null) {
      _ledger = ref
          .read(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: widget.fee.schoolId,
            branchId: widget.fee.branchId,
            studentId: widget.studentId!,
            academicYearId: widget.fee.year.academicYearId,
          );
      // Same query with no year filter: the cross-year position.
      _allYears = ref
          .read(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: widget.fee.schoolId,
            branchId: widget.fee.branchId,
            studentId: widget.studentId!,
          );
    }
    _apply();
  }

  void _apply() {
    final repo = ref.read(invoiceRepositoryProvider);
    final fee = widget.fee;
    _controller.fetch = _searching
        ? (cursor) => repo.searchInvoicesByNumber(
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            query: _search.text,
            cursor: cursor,
          )
        : (cursor) => repo.fetchInvoices(
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            filter: InvoiceFilter(
              academicYearId: fee.year.academicYearId,
              studentId: widget.studentId,
              classId: _classId,
              sectionId: _sectionId,
              status: switch (_status) {
                _StatusFilter.issued => InvoiceStatus.issued,
                _StatusFilter.partiallyPaid => InvoiceStatus.partiallyPaid,
                _StatusFilter.paid => InvoiceStatus.paid,
                _StatusFilter.voided => InvoiceStatus.voided,
                _ => null,
              },
              overdueOnly: _status == _StatusFilter.overdue,
              dueFromKey: _from,
              dueToKey: _to,
            ),
            cursor: cursor,
          );
    _controller.reload();
  }

  void _set(VoidCallback change) {
    setState(change);
    _apply();
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      _set(
        () => from
            ? _from = FeeDates.todayKey(picked)
            : _to = FeeDates.todayKey(picked),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final classes = (ref.watch(classesProvider(fee.yearKey)).value ?? const [])
        .where((c) => c.status.wireValue == 'ACTIVE')
        .toList();
    final sections = _classId == null
        ? const []
        : (ref
                  .watch(
                    sectionsProvider((
                      schoolId: fee.schoolId,
                      branchId: fee.branchId,
                      academicYearId: fee.year.academicYearId,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const []);
    final today = FeeDates.todayKey();

    Widget dropdown<T>(
      String label,
      T value,
      List<DropdownMenuItem<T>> items,
      ValueChanged<T?>? onChanged,
    ) => SizedBox(
      width: 170,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: _searching ? null : onChanged,
      ),
    );

    return Column(
      children: [
        if (_allYears != null)
          StudentAllYearsLedger(
            future: _allYears!,
            currency: fee.currency,
            selectedYearId: fee.year.academicYearId,
          ),
        if (_ledger != null)
          _LedgerSummary(future: _ledger!, currency: fee.currency),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText:
                            'Search by invoice number (e.g. INV-2026-0000)',
                        isDense: true,
                        suffixIcon: _searching
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _set(_search.clear),
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 400),
                          () {
                            if (mounted) _set(() {});
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (fee.tenant.can(Permission.issueInvoices))
                    FilledButton.icon(
                      onPressed: () => context.push('/fees/invoices/generate'),
                      icon: const Icon(Icons.add),
                      label: const Text('Generate'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  dropdown<_StatusFilter>('Status', _status, [
                    const DropdownMenuItem(
                      value: _StatusFilter.all,
                      child: Text('All statuses'),
                    ),
                    const DropdownMenuItem(
                      value: _StatusFilter.overdue,
                      child: Text('Overdue'),
                    ),
                    const DropdownMenuItem(
                      value: _StatusFilter.issued,
                      child: Text('Issued'),
                    ),
                    const DropdownMenuItem(
                      value: _StatusFilter.partiallyPaid,
                      child: Text('Partially paid'),
                    ),
                    const DropdownMenuItem(
                      value: _StatusFilter.paid,
                      child: Text('Paid'),
                    ),
                    const DropdownMenuItem(
                      value: _StatusFilter.voided,
                      child: Text('Void'),
                    ),
                  ], (v) => _set(() => _status = v ?? _status)),
                  if (widget.studentId == null) ...[
                    dropdown<String?>(
                      'Class',
                      classes.any((c) => c.classId == _classId)
                          ? _classId
                          : null,
                      [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All classes'),
                        ),
                        for (final c in classes)
                          DropdownMenuItem(
                            value: c.classId,
                            child: Text(c.name),
                          ),
                      ],
                      (v) => _set(() {
                        _classId = v;
                        _sectionId = null;
                      }),
                    ),
                    dropdown<String?>(
                      'Section',
                      sections.any((s) => s.sectionId == _sectionId)
                          ? _sectionId
                          : null,
                      [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All sections'),
                        ),
                        for (final s in sections)
                          DropdownMenuItem(
                            value: s.sectionId,
                            child: Text(s.name),
                          ),
                      ],
                      _classId == null
                          ? null
                          : (v) => _set(() => _sectionId = v),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: _searching ? null : () => _pick(true),
                    child: Text(
                      _from == null
                          ? 'Due from'
                          : 'From ${FeeDates.display(_from!)}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _searching ? null : () => _pick(false),
                    child: Text(
                      _to == null ? 'Due to' : 'To ${FeeDates.display(_to!)}',
                    ),
                  ),
                  if (_from != null || _to != null)
                    TextButton(
                      onPressed: () => _set(() => _from = _to = null),
                      child: const Text('Clear dates'),
                    ),
                ],
              ),
              if (_searching)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Filters are paused while searching.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.errorMessage != null &&
                  _controller.items.isEmpty) {
                return ErrorView(
                  message: _controller.errorMessage!,
                  onRetry: _controller.reload,
                );
              }
              if (!_controller.hasLoaded) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveDataList<Invoice>(
                      items: _controller.items,
                      columnHeaders: const [
                        'Invoice',
                        'Student',
                        'Class',
                        'Period',
                        'Due',
                        'Payable',
                        'Paid',
                        'Balance',
                        'Status',
                      ],
                      emptyState: const EmptyView(
                        icon: Icons.receipt_long_outlined,
                        message: 'No invoices found.',
                      ),
                      cellsBuilder: (i) => [
                        DataCell(
                          Text(i.invoiceNumber),
                          onTap: () =>
                              context.push('/fees/invoices/${i.invoiceId}'),
                        ),
                        DataCell(Text(i.studentName)),
                        DataCell(
                          Text('${i.className} ${i.sectionName}'.trim()),
                        ),
                        DataCell(Text(i.periodLabel)),
                        DataCell(Text(FeeDates.display(i.dueDateKey))),
                        DataCell(
                          Text(
                            Money.format(i.payableMinor, currency: i.currency),
                          ),
                        ),
                        DataCell(
                          Text(Money.format(i.paidMinor, currency: i.currency)),
                        ),
                        DataCell(
                          Text(
                            Money.format(i.balanceMinor, currency: i.currency),
                          ),
                        ),
                        DataCell(
                          InvoiceStatusChip(invoice: i, todayKey: today),
                        ),
                      ],
                      cardBuilder: (i) => Card(
                        child: ListTile(
                          title: Text('${i.invoiceNumber} · ${i.studentName}'),
                          subtitle: Text(
                            '${i.periodLabel} · due ${FeeDates.display(i.dueDateKey)}\nBalance ${Money.format(i.balanceMinor, currency: i.currency)} of ${Money.format(i.payableMinor, currency: i.currency)}',
                          ),
                          isThreeLine: true,
                          trailing: InvoiceStatusChip(
                            invoice: i,
                            todayKey: today,
                          ),
                          onTap: () =>
                              context.push('/fees/invoices/${i.invoiceId}'),
                        ),
                      ),
                    ),
                  ),
                  if (_controller.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        _controller.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_controller.hasMore)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: OutlinedButton(
                        onPressed: _controller.isLoading
                            ? null
                            : _controller.loadMore,
                        child: _controller.isLoading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Load more'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The student-wise ledger header: what was billed, paid, waived and is still
/// owed for the year, split into overdue and upcoming. Void invoices are
/// excluded.
class _LedgerSummary extends StatelessWidget {
  final Future<List<Invoice>> future;
  final String currency;

  const _LedgerSummary({required this.future, required this.currency});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Invoice>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final summary = StudentFeeSummary.of(
          snapshot.data!,
          todayKey: FeeDates.todayKey(),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              MetricCard(
                label: 'Billed',
                value: Money.format(summary.payableMinor, currency: currency),
              ),
              MetricCard(
                label: 'Paid',
                value: Money.format(summary.paidMinor, currency: currency),
              ),
              MetricCard(
                label: 'Waived',
                value: Money.format(summary.waivedMinor, currency: currency),
              ),
              MetricCard(
                label: 'Balance',
                value: Money.format(summary.balanceMinor, currency: currency),
              ),
              MetricCard(
                label: 'Overdue',
                value: Money.format(summary.overdueMinor, currency: currency),
              ),
              MetricCard(
                label: 'Upcoming',
                value: Money.format(summary.upcomingMinor, currency: currency),
              ),
            ],
          ),
        );
      },
    );
  }
}
