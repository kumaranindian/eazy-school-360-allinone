import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/date_formatting.dart';
import 'package:flutter/material.dart';
import '../../../../core/regional/regional_providers.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/branding/page_hero.dart';
import '../../../../shared/dashboard/home_widgets.dart';
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
/// invoices, payments and receipts. There is no online payment yet: open
/// invoices show a "Pay online — Coming soon" entry.
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

class _Child extends ConsumerStatefulWidget {
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
  ConsumerState<_Child> createState() => _ChildState();
}

enum _FeeTab { overview, invoices, receipts }

class _ChildState extends ConsumerState<_Child> {
  _FeeTab _tab = _FeeTab.overview;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final children = widget.children;
    final yearId = widget.yearId;
    final onChild = widget.onChild;
    final onYear = widget.onYear;
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
        final currency =
            invoices.firstOrNull?.currency ??
            ref.watch(regionalSettingsProvider).currency;

        final theme = Theme.of(context);
        final clear = summary.balanceMinor == 0;
        final showInvoices = _tab != _FeeTab.receipts;
        final showPayments = _tab != _FeeTab.invoices;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHero(
                      title: 'Fees & Payments',
                      subtitle: 'Invoices, payments and receipts',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    HomePanel(
                      accent: context.brandTone(AppColors.accent),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              child.firstName.isEmpty
                                  ? '?'
                                  : child.firstName.characters.first
                                        .toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              child.displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (years.length > 1)
                            DropdownButton<String>(
                              value: selectedYear,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final e in years.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                              onChanged: onYear,
                            ),
                        ],
                      ),
                    ),
                    if (children.length > 1) ...[
                      const SizedBox(height: AppSpacing.sm),
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
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    HomePanel(
                      accent: context.brandTone(AppColors.accent),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                      child: Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _Figure(
                                    icon: Icons.receipt_long_outlined,
                                    color: context.brandTone(AppColors.accent),
                                    label: 'Total billed',
                                    value: Money.format(
                                      summary.payableMinor,
                                      currency: currency,
                                    ),
                                  ),
                                ),
                                VerticalDivider(
                                  width: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                Expanded(
                                  child: _Figure(
                                    icon: Icons.check_circle_outline,
                                    color: AppColors.success,
                                    label: 'Paid',
                                    value: Money.format(
                                      summary.paidMinor,
                                      currency: currency,
                                    ),
                                  ),
                                ),
                                VerticalDivider(
                                  width: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                Expanded(
                                  child: _Figure(
                                    icon: Icons.balance_outlined,
                                    color: clear
                                        ? AppColors.success
                                        : AppColors.warning,
                                    label: 'Balance due',
                                    value: Money.format(
                                      summary.balanceMinor,
                                      currency: currency,
                                    ),
                                    pill: clear ? 'All clear' : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 20),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _Figure(
                                    icon: Icons.warning_amber_rounded,
                                    color: summary.overdueMinor > 0
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.outline,
                                    label: 'Overdue',
                                    value: Money.format(
                                      summary.overdueMinor,
                                      currency: currency,
                                    ),
                                    small: true,
                                  ),
                                ),
                                Expanded(
                                  child: _Figure(
                                    icon: Icons.event_outlined,
                                    color: theme.colorScheme.outline,
                                    label: 'Upcoming',
                                    value: Money.format(
                                      summary.upcomingMinor,
                                      currency: currency,
                                    ),
                                    small: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _FeeTabs(
                      selected: _tab,
                      onSelected: (t) => setState(() => _tab = t),
                    ),
                    if (_tab == _FeeTab.overview) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _StatusBanner(
                        clear: clear,
                        overdue: summary.overdueMinor > 0,
                      ),
                    ],
                    if (_tab == _FeeTab.overview) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Assigned(child: child, yearId: selectedYear),
                    ],
                    if (showInvoices) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Invoices',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (invoices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Text('No invoices yet.'),
                        ),
                      for (final i in invoices)
                        Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                title: Text(
                                  '${i.invoiceNumber} · ${i.periodLabel}',
                                ),
                                subtitle: Text(
                                  'Due ${FeeDates.display(i.dueDateKey)} · Balance ${Money.format(i.balanceMinor, currency: i.currency)} of ${Money.format(i.payableMinor, currency: i.currency)}',
                                ),
                                trailing: InvoiceStatusChip(
                                  invoice: i,
                                  todayKey: today,
                                ),
                                onTap: () => context.push(
                                  '/my-fees/invoices/${i.invoiceId}?b=${i.branchId}',
                                ),
                              ),
                              if (invoiceAwaitsPayment(i))
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    0,
                                    AppSpacing.md,
                                    AppSpacing.sm,
                                  ),
                                  child: PayOnlineComingSoon(),
                                ),
                            ],
                          ),
                        ),
                    ],
                    if (showPayments) ...[
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
                  ],
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

/// One headline figure of the fee summary: icon, label, amount (and an
/// optional "All clear" pill).
class _Figure extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? pill;
  final bool small;

  const _Figure({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.pill,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: small ? 20 : 28),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style:
                  (small
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pill != null ? color : null,
                      ),
            ),
          ),
          if (pill != null) ...[
            const SizedBox(height: 4),
            StatusPill(pill!, icon: Icons.check),
          ],
        ],
      ),
    );
  }
}

/// Overview / Invoices / Receipts switch.
class _FeeTabs extends StatelessWidget {
  final _FeeTab selected;
  final ValueChanged<_FeeTab> onSelected;

  const _FeeTabs({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tab(_FeeTab t, IconData icon, String label) {
      final on = t == selected;
      final fg = on ? Colors.white : theme.colorScheme.onSurface;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on
                ? context.brandTone(AppColors.primary)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onSelected(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          tab(_FeeTab.overview, Icons.bar_chart_rounded, 'Overview'),
          tab(_FeeTab.invoices, Icons.description_outlined, 'Invoices'),
          tab(_FeeTab.receipts, Icons.receipt_outlined, 'Receipts'),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool clear;
  final bool overdue;

  const _StatusBanner({required this.clear, required this.overdue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = clear
        ? AppColors.success
        : (overdue ? theme.colorScheme.error : AppColors.warning);
    return HomePanel(
      accent: color,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: Icon(
              clear ? Icons.check : Icons.priority_high,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clear
                      ? 'No outstanding fees'
                      : (overdue ? 'Some fees are overdue' : 'Fees are due'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  clear
                      ? "You're all caught up"
                      : 'See the invoices below for amounts and due dates',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
