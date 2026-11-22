import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../expenses/domain/expense.dart' show PaymentMode;
import '../../../expenses/presentation/pages/expense_reports_page.dart'
    show expenseCsvSaverProvider;
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/payroll_preview.dart';
import '../providers/payroll_providers.dart';

/// `/payroll/register`: what the branch actually PAID, month by month, with
/// the Salaries expense each month was recorded as, and a CSV of any month's
/// payslips (one row per person, one column per pay component).
class PayrollRegisterPage extends ConsumerWidget {
  const PayrollRegisterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll register')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _Register(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _Register extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;

  const _Register({super.key, required this.schoolId, required this.branchId});

  @override
  ConsumerState<_Register> createState() => _RegisterState();
}

class _RegisterState extends ConsumerState<_Register> {
  late final List<String> _periods;
  late String _from;
  late String _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periods = recentPeriods(now.year, now.month, count: 24);
    _to = _periods.first;
    _from = _periods[11];
  }

  RegisterKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    fromPeriod: _from,
    toPeriod: _to,
  );

  Future<void> _export(String period) async {
    try {
      final out = await ref
          .read(payrollRepositoryProvider)
          .exportRegister(widget.schoolId, widget.branchId, period);
      final saved = await ref
          .read(expenseCsvSaverProvider)
          .save('payroll_register_$period.csv', out.csv);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Saved ${out.rows} payslips.' : 'Nothing was saved.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(payrollRegisterProvider(_key));
    final text = Theme.of(context).textTheme;
    Widget picker(
      String key,
      String label,
      String value,
      ValueChanged<String> on,
    ) => DropdownButtonFormField<String>(
      key: ValueKey(key),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final p in _periods)
          DropdownMenuItem(value: p, child: Text(periodLabel(p))),
      ],
      onChanged: (v) {
        if (v != null) on(v);
      },
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 220,
                child: picker('register-from', 'From', _from, (v) {
                  setState(() {
                    _from = v;
                    if (_from.compareTo(_to) > 0) _to = _from;
                  });
                }),
              ),
              SizedBox(
                width: 220,
                child: picker('register-to', 'To', _to, (v) {
                  setState(() {
                    _to = v;
                    if (_from.compareTo(_to) > 0) _from = _to;
                  });
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: loaded.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(payrollRegisterProvider(_key)),
            ),
            data: (r) {
              if (r.rows.isEmpty) {
                return const EmptyView(
                  icon: Icons.table_chart_outlined,
                  message: 'Nothing was paid in these months.',
                );
              }
              String money(int v) => Money.format(v, currency: r.currency);
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Card(
                    key: const ValueKey('register-totals'),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r.runs} month${r.runs == 1 ? '' : 's'} paid',
                            style: text.titleSmall,
                          ),
                          Text(
                            'Net pay ${money(r.netMinor)}',
                            style: text.headlineSmall,
                          ),
                          Text(
                            'Earnings ${money(r.grossMinor)} · deductions ${money(r.deductionsMinor)}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final row in r.rows)
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            key: ValueKey('register-${row.period}'),
                            title: Text(periodLabel(row.period)),
                            subtitle: Text(
                              [
                                '${row.payslipCount} payslips',
                                if (row.paidDate != null)
                                  'paid ${row.paidDate}',
                                if (row.paymentMode != null)
                                  PaymentMode.fromWire(
                                        row.paymentMode,
                                      )?.label ??
                                      row.paymentMode!,
                                if (row.expenseNumber != null)
                                  row.expenseNumber!,
                              ].join(' · '),
                            ),
                            trailing: Text(
                              money(row.netMinor),
                              style: text.titleMedium,
                            ),
                            onTap: () =>
                                context.go('/payroll/runs/${row.period}'),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.sm,
                                bottom: AppSpacing.xs,
                              ),
                              child: TextButton.icon(
                                key: ValueKey('register-csv-${row.period}'),
                                onPressed: () => _export(row.period),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Download CSV'),
                              ),
                            ),
                          ),
                        ],
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
