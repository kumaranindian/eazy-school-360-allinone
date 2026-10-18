import '../../../../core/regional/school_time.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_row_actions.dart';
import '../widgets/fee_scope.dart';
import '../widgets/student_all_years_ledger.dart';
import '../widgets/fee_widgets.dart';
import '../../../../shared/layouts/scrollable_header.dart';

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
    final now = SchoolTime.wallNow();
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

  /// Built on demand: the filter sheet asks again after every change.
  List<FilterField> _filters(
    List<SchoolClass> classes,
    List<Section> sections,
  ) => [
    FilterField.dropdown<_StatusFilter>(
      label: 'Status',
      value: _status == _StatusFilter.all ? null : _status,
      options: const [
        (null, 'All statuses'),
        (_StatusFilter.overdue, 'Overdue'),
        (_StatusFilter.issued, 'Issued'),
        (_StatusFilter.partiallyPaid, 'Partially paid'),
        (_StatusFilter.paid, 'Paid'),
        (_StatusFilter.voided, 'Void'),
      ],
      onChanged: (v) => _set(() => _status = v ?? _StatusFilter.all),
    ),
    if (widget.studentId == null) ...[
      FilterField.dropdown<String>(
        label: 'Class',
        value: classes.any((c) => c.classId == _classId) ? _classId : null,
        options: [
          (null, 'All classes'),
          for (final c in classes) (c.classId, c.name),
        ],
        onChanged: (v) => _set(() {
          _classId = v;
          _sectionId = null;
        }),
      ),
      FilterField.dropdown<String>(
        label: 'Section',
        value: sections.any((s) => s.sectionId == _sectionId)
            ? _sectionId
            : null,
        options: [
          (null, 'All sections'),
          for (final s in sections) (s.sectionId, s.name),
        ],
        onChanged: _classId == null ? null : (v) => _set(() => _sectionId = v),
      ),
    ],
    FilterField.picker(
      label: 'Due from',
      value: _from == null ? null : FeeDates.display(_from!),
      onPick: () => _pick(true),
      onClear: () => _set(() => _from = null),
    ),
    FilterField.picker(
      label: 'Due to',
      value: _to == null ? null : FeeDates.display(_to!),
      onPick: () => _pick(false),
      onClear: () => _set(() => _to = null),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final classes = (ref.watch(classesProvider(fee.yearKey)).value ?? const [])
        .where((c) => c.status.wireValue == 'ACTIVE')
        .toList();
    final List<Section> sections = _classId == null
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: fee.tenant.can(Permission.issueInvoices)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/fees/invoices/generate'),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Generate invoices'),
            )
          : null,
      body: Column(
        children: [
          if (_allYears != null)
            StudentAllYearsLedger(
              future: _allYears!,
              currency: fee.currency,
              selectedYearId: fee.year.academicYearId,
            ),
          if (_ledger != null)
            _LedgerSummary(future: _ledger!, currency: fee.currency),
          ScrollableHeader(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilterBar(
                searchController: _search,
                searchHint: 'Search invoice number',
                onSearchChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    if (mounted) _set(() {});
                  });
                  setState(() {});
                },
                filtersEnabled: !_searching,
                fieldsBuilder: () => _filters(classes, sections),
              ),
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
                          'Period',
                          'Due',
                          'Payable',
                          'Paid',
                          'Balance',
                          'Status',
                        ],
                        // A tablet keeps what identifies the invoice, what is
                        // owed and its status. Collect is in the first column,
                        // so it is on screen at any width.
                        tabletColumns: const [0, 1, 6, 7],
                        emptyState: const EmptyView(
                          icon: Icons.receipt_long_outlined,
                          message: 'No invoices found.',
                        ),
                        cellsBuilder: (i) => [
                          DataCell(
                            InvoiceNumberCell(invoice: i, tenant: fee.tenant),
                          ),
                          // The class sits beside the name, so the Actions
                          // column stays inside the window instead of past
                          // its right edge.
                          DataCell(
                            Text(
                              [
                                i.studentName,
                                '${i.className} ${i.sectionName}'.trim(),
                              ].where((p) => p.isNotEmpty).join(' · '),
                            ),
                          ),
                          DataCell(Text(i.periodLabel)),
                          DataCell(Text(FeeDates.display(i.dueDateKey))),
                          DataCell(
                            Text(
                              Money.format(
                                i.payableMinor,
                                currency: i.currency,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              Money.format(i.paidMinor, currency: i.currency),
                            ),
                          ),
                          DataCell(
                            Text(
                              Money.format(
                                i.balanceMinor,
                                currency: i.currency,
                              ),
                            ),
                          ),
                          DataCell(
                            InvoiceStatusChip(invoice: i, todayKey: today),
                          ),
                        ],
                        cardBuilder: (i) => Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                title: Text(
                                  '${i.invoiceNumber} · ${i.studentName}',
                                ),
                                subtitle: Text(
                                  '${i.periodLabel} · due ${FeeDates.display(i.dueDateKey)}\nBalance ${Money.format(i.balanceMinor, currency: i.currency)} of ${Money.format(i.payableMinor, currency: i.currency)}',
                                ),
                                isThreeLine: true,
                                trailing: InvoiceStatusChip(
                                  invoice: i,
                                  todayKey: today,
                                ),
                                onTap: () => context.push(
                                  '/fees/invoices/${i.invoiceId}',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.sm,
                                  AppSpacing.sm,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: InvoiceRowActions(
                                    invoice: i,
                                    tenant: fee.tenant,
                                  ),
                                ),
                              ),
                            ],
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
      ),
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
