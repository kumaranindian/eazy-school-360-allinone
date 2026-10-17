import '../../../../core/utils/date_formatting.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/parent_providers.dart';
import '../../../students/presentation/providers/student_providers.dart'
    show parentAccessEnsuredProvider;
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_widgets.dart';
import 'invoice_detail_page.dart';
import 'receipt_page.dart';

/// The children linked to the signed-in parent's record that they may open
/// (an ACTIVE, portal-enabled link). Which records are readable is decided by
/// `firestore.rules`, not by this list.
final linkedChildrenProvider = FutureProvider.autoDispose
    .family<List<Student>, ({String schoolId, String parentId})>((
      ref,
      key,
    ) async {
      await ref.watch(parentAccessEnsuredProvider(key.parentId).future);
      return ref
          .watch(parentRepositoryProvider)
          .getChildrenForParent(schoolId: key.schoolId, parentId: key.parentId);
    });

class _ChildFees {
  final List<Invoice> invoices;
  final List<Payment> payments;

  const _ChildFees(this.invoices, this.payments);
}

typedef _ChildKey = ({String schoolId, String branchId, String studentId});

final _childFeesProvider = FutureProvider.autoDispose
    .family<_ChildFees, _ChildKey>((ref, key) async {
      final invoices = await ref
          .watch(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      final payments = await ref
          .watch(paymentRepositoryProvider)
          .fetchStudentPayments(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      return _ChildFees(invoices, payments);
    });

/// `/my-fees` — a parent's read-only view of their linked children's fees,
/// invoices, payments and receipts. There is no online payment here.
class ParentFeesPage extends ConsumerStatefulWidget {
  const ParentFeesPage({super.key});

  @override
  ConsumerState<ParentFeesPage> createState() => _ParentFeesPageState();
}

class _ParentFeesPageState extends ConsumerState<ParentFeesPage> {
  String? _childId;
  String? _yearId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My children\'s fees')),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final parentId = tenant?.user.linkedParentId;
          if (tenant == null || schoolId == null) {
            return const EmptyView(
              icon: Icons.family_restroom_outlined,
              message: 'No school found for your account.',
            );
          }
          if (parentId == null) {
            return const EmptyView(
              icon: Icons.link_off,
              message:
                  "Your account isn't linked to a parent record yet. Please contact the school office.",
            );
          }
          final childrenAsync = ref.watch(
            linkedChildrenProvider((schoolId: schoolId, parentId: parentId)),
          );
          return childrenAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorView(
              message: userMessageFor(error),
              onRetry: () => ref.invalidate(linkedChildrenProvider),
            ),
            data: (children) {
              if (children.isEmpty) {
                return const EmptyView(
                  icon: Icons.child_care_outlined,
                  message:
                      'No children are linked to your account with fee access yet.',
                );
              }
              final child = children.firstWhere(
                (c) => c.studentId == _childId,
                orElse: () => children.first,
              );
              return _Child(
                tenant: tenant,
                children: children,
                child: child,
                yearId: _yearId,
                onChild: (id) => setState(() {
                  _childId = id;
                  _yearId = null;
                }),
                onYear: (y) => setState(() => _yearId = y),
              );
            },
          );
        },
      ),
    );
  }
}

class _Child extends ConsumerWidget {
  final TenantContext tenant;
  final List<Student> children;
  final Student child;
  final String? yearId;
  final ValueChanged<String> onChild;
  final ValueChanged<String?> onYear;

  const _Child({
    required this.tenant,
    required this.children,
    required this.child,
    required this.yearId,
    required this.onChild,
    required this.onYear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: child.schoolId,
      branchId: child.branchId,
      studentId: child.studentId,
    );
    final feesAsync = ref.watch(_childFeesProvider(key));
    final today = FeeDates.todayKey();

    return feesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(_childFeesProvider(key)),
      ),
      data: (fees) {
        final years = <String, String>{
          for (final i in fees.invoices) i.academicYearId: i.academicYearName,
        };
        if (child.currentAcademicYearId != null) {
          years.putIfAbsent(
            child.currentAcademicYearId!,
            () => 'Current academic year',
          );
        }
        final selectedYear = years.containsKey(yearId)
            ? yearId
            : (years.keys.isEmpty ? null : years.keys.first);
        final invoices = fees.invoices
            .where(
              (i) => selectedYear == null || i.academicYearId == selectedYear,
            )
            .toList();
        final payments = fees.payments
            .where(
              (p) => selectedYear == null || p.academicYearId == selectedYear,
            )
            .toList();
        final summary = StudentFeeSummary.of(invoices, todayKey: today);
        final currency = invoices.firstOrNull?.currency ?? 'INR';

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (children.length > 1)
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final c in children)
                    ChoiceChip(
                      label: Text(c.displayName),
                      selected: c.studentId == child.studentId,
                      onSelected: (_) => onChild(c.studentId),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    child.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (years.length > 1)
                  DropdownButton<String>(
                    value: selectedYear,
                    items: [
                      for (final e in years.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: onYear,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                MetricCard(
                  label: 'Total billed',
                  value: Money.format(summary.payableMinor, currency: currency),
                ),
                MetricCard(
                  label: 'Paid',
                  value: Money.format(summary.paidMinor, currency: currency),
                  color: AppColors.success,
                ),
                MetricCard(
                  label: 'Balance due',
                  value: Money.format(summary.balanceMinor, currency: currency),
                ),
                MetricCard(
                  label: 'Overdue',
                  value: Money.format(summary.overdueMinor, currency: currency),
                  color: summary.overdueMinor > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                MetricCard(
                  label: 'Upcoming',
                  value: Money.format(
                    summary.upcomingMinor,
                    currency: currency,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Assigned(child: child, yearId: selectedYear),
            const SizedBox(height: AppSpacing.md),
            Text('Invoices', style: Theme.of(context).textTheme.titleMedium),
            if (invoices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('No invoices yet.'),
              ),
            for (final i in invoices)
              Card(
                child: ListTile(
                  title: Text('${i.invoiceNumber} · ${i.periodLabel}'),
                  subtitle: Text(
                    'Due ${FeeDates.display(i.dueDateKey)} · Balance ${Money.format(i.balanceMinor, currency: i.currency)} of ${Money.format(i.payableMinor, currency: i.currency)}',
                  ),
                  trailing: InvoiceStatusChip(invoice: i, todayKey: today),
                  onTap: () => context.push(
                    '/my-fees/invoices/${i.invoiceId}?b=${i.branchId}',
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Payments & receipts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (payments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('No payments yet.'),
              ),
            for (final p in payments)
              Card(
                child: ListTile(
                  title: Text(
                    '${p.receiptNumber} · ${Money.format(p.amountMinor, currency: currency)}',
                  ),
                  subtitle: Text(
                    '${FeeDates.display(p.paymentDateKey)} · ${p.methodDisplay} · ${p.invoiceNumber} · Recorded ${formatInstant(p.createdAt)}',
                  ),
                  trailing: PaymentStatusChip(status: p.status),
                  onTap: () => context.push(
                    '/my-fees/receipts/${p.paymentId}?b=${p.branchId}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Assigned extends ConsumerWidget {
  final Student child;
  final String? yearId;

  const _Assigned({required this.child, required this.yearId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (yearId == null) return const SizedBox.shrink();
    final assignments = ref.watch(
      studentAssignmentsProvider((
        schoolId: child.schoolId,
        branchId: child.branchId,
        studentId: child.studentId,
        academicYearId: yearId!,
      )),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assigned fees', style: Theme.of(context).textTheme.titleMedium),
        assignments.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(userMessageFor(error)),
          data: (list) {
            final active = list.where((a) => a.isActive).toList();
            if (active.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text('No fees assigned.'),
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final a in active)
                  Chip(
                    label: Text(
                      a.hasConcession
                          ? '${a.structureName} (${a.concessionType == ConcessionType.percent ? '${(a.concessionValue / 100).toStringAsFixed(0)}% concession' : 'concession'})'
                          : a.structureName,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `/my-fees/invoices/:id?b=<branch>` — the parent's read-only invoice view.
class ParentInvoicePage extends ConsumerWidget {
  final String invoiceId;
  final String? branchId;

  const ParentInvoicePage({super.key, required this.invoiceId, this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final branch = branchId ?? tenant?.branch?.branchId;
          if (tenant == null || schoolId == null || branch == null) {
            return const EmptyView(message: 'This invoice could not be found.');
          }
          return InvoiceDetailBody(
            tenant: tenant,
            schoolId: schoolId,
            branchId: branch,
            invoiceId: invoiceId,
            parentView: true,
          );
        },
      ),
    );
  }
}

/// `/my-fees/receipts/:id?b=<branch>` — the parent's read-only receipt view.
class ParentReceiptPage extends ConsumerWidget {
  final String receiptId;
  final String? branchId;

  const ParentReceiptPage({super.key, required this.receiptId, this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final branch = branchId ?? tenant?.branch?.branchId;
          if (tenant == null || schoolId == null || branch == null) {
            return const EmptyView(message: 'This receipt could not be found.');
          }
          return ReceiptBody(
            tenant: tenant,
            schoolId: schoolId,
            branchId: branch,
            receiptId: receiptId,
          );
        },
      ),
    );
  }
}
