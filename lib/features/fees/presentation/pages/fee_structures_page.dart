import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_structure.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/copy_structures_dialog.dart';
import '../widgets/fee_scope.dart';
import '../widgets/fee_structure_form_dialog.dart';

/// `/fees/structures` — fee heads for the chosen academic year. Anyone with
/// `viewFees` can read them; only `manageFeeStructures` holders get the
/// add/edit controls (the rules enforce it regardless).
///
/// Search and the category chips only narrow the list already loaded for the
/// year; nothing here changes what is read or written.
class FeeStructuresPage extends ConsumerStatefulWidget {
  const FeeStructuresPage({super.key});

  @override
  ConsumerState<FeeStructuresPage> createState() => _FeeStructuresPageState();
}

class _FeeStructuresPageState extends ConsumerState<FeeStructuresPage> {
  bool _showInactive = false;
  String _query = '';
  FeeCategory? _category;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  IconData _icon(FeeCategory c) => switch (c) {
    FeeCategory.tuition => Icons.school_outlined,
    FeeCategory.admission => Icons.how_to_reg_outlined,
    FeeCategory.examination => Icons.fact_check_outlined,
    FeeCategory.transport => Icons.directions_bus_outlined,
    FeeCategory.books => Icons.menu_book_outlined,
    FeeCategory.uniform => Icons.checkroom_outlined,
    FeeCategory.activity => Icons.sports_soccer_outlined,
    FeeCategory.other => Icons.sell_outlined,
  };

  Color _color(FeeCategory c) => switch (c) {
    FeeCategory.tuition => AppColors.accent,
    FeeCategory.admission => AppColors.success,
    FeeCategory.examination => AppColors.secondary,
    FeeCategory.transport => AppColors.gold,
    FeeCategory.books => AppColors.teal,
    FeeCategory.uniform => AppColors.orange,
    FeeCategory.activity => AppColors.orange,
    FeeCategory.other => AppColors.secondary,
  };

  Future<void> _filters() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: SwitchListTile(
          title: const Text('Show inactive fees'),
          value: _showInactive,
          onChanged: (v) {
            setState(() => _showInactive = v);
            setSheet(() {});
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fee structures')),
      body: FeeScope(
        builder: (context, fee) {
          final canManage = fee.tenant.can(Permission.manageFeeStructures);
          final structures = ref.watch(feeStructuresProvider(fee.yearKey));
          final classNames = {
            for (final c
                in ref.watch(classesProvider(fee.yearKey)).value ?? const [])
              c.classId: c.name,
          };

          Future<void> open({FeeStructure? existing}) async {
            final saved = await showFeeStructureForm(
              context,
              fee: fee,
              existing: existing,
            );
            if (saved == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    existing == null
                        ? 'Fee created successfully.'
                        : 'Fee updated successfully.',
                  ),
                ),
              );
            }
          }

          String appliesTo(FeeStructure s) => s.classId == null
              ? 'All classes'
              : (classNames[s.classId] ?? 'Class') +
                    (s.sectionId == null ? '' : ' (one section)');

          return Stack(
            children: [
              AsyncValueWidget(
                value: structures,
                errorMessage: userMessageFor,
                data: (all) {
                  final visible = all
                      .where((s) => _showInactive || s.isActive)
                      .toList();
                  final q = _query.trim().toLowerCase();
                  final list = [
                    for (final s in visible)
                      if ((_category == null || s.category == _category) &&
                          (q.isEmpty ||
                              s.name.toLowerCase().contains(q) ||
                              s.code.toLowerCase().contains(q)))
                        s,
                  ];
                  final categories = [
                    for (final c in FeeCategory.values)
                      if (visible.any((s) => s.category == c)) c,
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      96,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (canManage)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: () => showDialog<bool>(
                                      context: context,
                                      builder: (context) =>
                                          CopyStructuresDialog(fee: fee),
                                    ),
                                    icon: const Icon(Icons.copy_all_outlined),
                                    label: const Text('Copy from another year'),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _search,
                                      onChanged: (v) =>
                                          setState(() => _query = v),
                                      decoration: const InputDecoration(
                                        hintText: 'Search fee heads…',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  IconButton.outlined(
                                    tooltip: 'Filters',
                                    onPressed: _filters,
                                    icon: Icon(
                                      _showInactive
                                          ? Icons.filter_alt
                                          : Icons.filter_alt_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SizedBox(
                                height: 48,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    _CategoryChip(
                                      label: 'All',
                                      count: visible.length,
                                      selected: _category == null,
                                      onTap: () =>
                                          setState(() => _category = null),
                                    ),
                                    for (final c in categories)
                                      _CategoryChip(
                                        label: c.displayName,
                                        count: visible
                                            .where((s) => s.category == c)
                                            .length,
                                        selected: _category == c,
                                        onTap: () =>
                                            setState(() => _category = c),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (all.isEmpty)
                                EmptyView(
                                  icon: Icons.sell_outlined,
                                  message:
                                      'No fees configured for this academic year.${canManage ? ' Add the first one.' : ''}',
                                )
                              else if (list.isEmpty)
                                const EmptyView(
                                  icon: Icons.search_off,
                                  message: 'No fee heads match your search.',
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final cols = constraints.maxWidth >= 760
                                        ? 2
                                        : 1;
                                    return Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < list.length;
                                          i += cols
                                        ) ...[
                                          if (i > 0)
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                          IntrinsicHeight(
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                for (
                                                  var c = 0;
                                                  c < cols;
                                                  c++
                                                ) ...[
                                                  if (c > 0)
                                                    const SizedBox(
                                                      width: AppSpacing.sm,
                                                    ),
                                                  Expanded(
                                                    child: i + c < list.length
                                                        ? _FeeCard(
                                                            s: list[i + c],
                                                            currency:
                                                                fee.currency,
                                                            applies: appliesTo(
                                                              list[i + c],
                                                            ),
                                                            icon: _icon(
                                                              list[i + c]
                                                                  .category,
                                                            ),
                                                            color: _color(
                                                              list[i + c]
                                                                  .category,
                                                            ),
                                                            canManage:
                                                                canManage,
                                                            onEdit: () => open(
                                                              existing:
                                                                  list[i + c],
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Showing ${list.length} fee ${list.length == 1 ? 'head' : 'heads'}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (canManage)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () => open(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add fee'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.primary : theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? AppColors.primaryLight
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '($count)',
                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  final FeeStructure s;
  final String currency;
  final String applies;
  final IconData icon;
  final Color color;
  final bool canManage;
  final VoidCallback onEdit;

  const _FeeCard({
    required this.s,
    required this.currency,
    required this.applies,
    required this.icon,
    required this.color,
    required this.canManage,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: s.isActive ? color : null,
      onTap: canManage ? onEdit : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name + (s.isOptional ? ' (optional)' : ''),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(s.code, style: theme.textTheme.bodySmall),
                Text(
                  '${s.frequency.displayName} • $applies',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(s.amountMinor, currency: currency),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              StatusPill(
                s.isActive ? 'Active' : 'Inactive',
                color: s.isActive
                    ? AppColors.success
                    : theme.colorScheme.outline,
              ),
            ],
          ),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => onEdit(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
              ],
            ),
        ],
      ),
    );
  }
}
