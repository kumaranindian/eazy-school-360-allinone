import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';
import '../widgets/fee_widgets.dart';

/// `/fees/payments` — payment and receipt history for the year, newest first,
/// filterable by status (reversed payments stay listed, marked), method and
/// date range; cursor-paginated.
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments & receipts')),
      body: FeeScope(builder: (context, fee) => _Payments(fee: fee)),
    );
  }
}

class _Payments extends ConsumerStatefulWidget {
  final FeeContext fee;

  const _Payments({required this.fee});

  @override
  ConsumerState<_Payments> createState() => _PaymentsState();
}

class _PaymentsState extends ConsumerState<_Payments> {
  final _controller = PagedListController<Payment>();
  PaymentStatus? _status;
  PaymentMethod? _method;
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    _apply();
  }

  void _apply() {
    final fee = widget.fee;
    final repo = ref.read(paymentRepositoryProvider);
    _controller.fetch = (cursor) => repo.fetchPayments(
      schoolId: fee.schoolId,
      branchId: fee.branchId,
      academicYearId: fee.year.academicYearId,
      status: _status,
      method: _method,
      fromKey: _from,
      toKey: _to,
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
      lastDate: now,
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<PaymentStatus?>(
                  value: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final s in PaymentStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.displayName)),
                  ],
                  onChanged: (v) => _set(() => _status = v),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<PaymentMethod?>(
                  value: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All methods'),
                    ),
                    for (final m in PaymentMethod.values)
                      DropdownMenuItem(value: m, child: Text(m.displayName)),
                  ],
                  onChanged: (v) => _set(() => _method = v),
                ),
              ),
              OutlinedButton(
                onPressed: () => _pick(true),
                child: Text(
                  _from == null ? 'From' : 'From ${FeeDates.display(_from!)}',
                ),
              ),
              OutlinedButton(
                onPressed: () => _pick(false),
                child: Text(
                  _to == null ? 'To' : 'To ${FeeDates.display(_to!)}',
                ),
              ),
              if (_from != null || _to != null)
                TextButton(
                  onPressed: () => _set(() => _from = _to = null),
                  child: const Text('Clear dates'),
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
                    child: ResponsiveDataList<Payment>(
                      items: _controller.items,
                      columnHeaders: const [
                        'Receipt',
                        'Date',
                        'Student',
                        'Invoice',
                        'Method',
                        'Amount',
                        'Collected by',
                        'Status',
                      ],
                      emptyState: const EmptyView(
                        icon: Icons.payments_outlined,
                        message: 'No payments found.',
                      ),
                      cellsBuilder: (p) => [
                        DataCell(
                          Text(p.receiptNumber),
                          onTap: () =>
                              context.push('/fees/receipts/${p.paymentId}'),
                        ),
                        DataCell(Text(FeeDates.display(p.paymentDateKey))),
                        DataCell(Text(p.studentName)),
                        DataCell(
                          Text(p.invoiceNumber),
                          onTap: () =>
                              context.push('/fees/invoices/${p.invoiceId}'),
                        ),
                        DataCell(Text(p.methodDisplay)),
                        DataCell(
                          Text(
                            Money.format(p.amountMinor, currency: fee.currency),
                          ),
                        ),
                        DataCell(Text(p.collectorName)),
                        DataCell(PaymentStatusChip(status: p.status)),
                      ],
                      cardBuilder: (p) => Card(
                        child: ListTile(
                          title: Text(
                            '${p.receiptNumber} · ${Money.format(p.amountMinor, currency: fee.currency)}',
                          ),
                          subtitle: Text(
                            '${p.studentName} · ${p.methodDisplay} · ${FeeDates.display(p.paymentDateKey)}',
                          ),
                          trailing: PaymentStatusChip(status: p.status),
                          onTap: () =>
                              context.push('/fees/receipts/${p.paymentId}'),
                        ),
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
