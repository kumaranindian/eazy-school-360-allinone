import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../fees/domain/money.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_ops_providers.dart';
import '../widgets/billing_dialogs.dart';
import '../widgets/platform_scaffold.dart';
import '../widgets/school_lifecycle_panels.dart';

/// What every school owes Avail404 (manual records). Owner only.
class PlatformBillingPage extends ConsumerStatefulWidget {
  const PlatformBillingPage({super.key});

  @override
  ConsumerState<PlatformBillingPage> createState() =>
      _PlatformBillingPageState();
}

class _PlatformBillingPageState extends ConsumerState<PlatformBillingPage> {
  String? _status = 'DUE';

  @override
  Widget build(BuildContext context) {
    final owner =
        ref.watch(tenantContextProvider).value?.user.platformRole ==
        PlatformRole.owner;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    return PlatformScaffold(
      title: 'Billing',
      child: !owner
          ? const EmptyView(
              icon: Icons.lock_outline,
              message: 'Only a platform owner can see billing.',
            )
          : AsyncValueWidget(
              value: ref.watch(billingProvider(null)),
              errorMessage: userMessageFor,
              onRetry: () => ref.invalidate(billingProvider(null)),
              data: (b) {
                final today = dayKey(DateTime.now());
                final shown = [
                  for (final r in b.records)
                    if (_status == null || r.status == _status) r,
                ];
                return PlatformBody(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      if (b.owed.isEmpty)
                        Text(
                          'Nothing is owed.',
                          key: const ValueKey('billing-none'),
                          style: text.titleMedium,
                        )
                      else
                        for (final e in b.owed.entries)
                          Text(
                            'Owed ${Money.format(e.value.dueMinor, currency: e.key)}'
                            '${e.value.overdueMinor > 0 ? ' · overdue ${Money.format(e.value.overdueMinor, currency: e.key)}' : ''}',
                            key: ValueKey('owed-${e.key}'),
                            style: text.titleMedium,
                          ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          for (final f in <(String?, String)>[
                            (null, 'All'),
                            ('DUE', 'Due'),
                            ('PAID', 'Paid'),
                            ('WAIVED', 'Waived'),
                            ('VOID', 'Void'),
                          ])
                            ChoiceChip(
                              key: ValueKey('billing-filter-${f.$1 ?? 'all'}'),
                              label: Text(f.$2),
                              selected: _status == f.$1,
                              onSelected: (_) => setState(() => _status = f.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (shown.isEmpty)
                        const EmptyView(
                          icon: Icons.receipt_long_outlined,
                          message: 'No records.',
                        ),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Column(
                            children: [
                              for (final r in shown)
                                BillingRecordTile(
                                  record: r,
                                  todayKey: today,
                                  busy: busy,
                                  showSchool: true,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Add a record from the school\'s own page (Schools → the school → Billing).',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
