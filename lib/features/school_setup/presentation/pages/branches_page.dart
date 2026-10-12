import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/branch.dart';
import '../../domain/branch_status.dart';
import '../providers/school_profile_providers.dart';
import '../providers/school_providers.dart';
import '../widgets/branch_form_dialog.dart';

class BranchesPage extends ConsumerStatefulWidget {
  const BranchesPage({super.key});

  @override
  ConsumerState<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends ConsumerState<BranchesPage> {
  String _search = '';
  BranchStatus? _statusFilter;

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String userId,
    List<Branch> all, {
    Branch? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => BranchFormDialog(
        schoolId: schoolId,
        currentUserId: userId,
        existing: existing,
        siblingsForValidation: all,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Branch created.' : 'Branch updated.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleStatus(Branch branch, String userId) async {
    final updated = branch.copyWith(
      status: branch.status == BranchStatus.active
          ? BranchStatus.inactive
          : BranchStatus.active,
    );
    await ref
        .read(schoolProfileWriteControllerProvider.notifier)
        .updateBranch(updated, updatedBy: userId);
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.apartment_outlined,
            message: 'No school found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final canManage = tenant.can(Permission.manageBranches);

        return StreamBuilder<List<Branch>>(
          stream: ref.watch(schoolRepositoryProvider).watchBranches(schoolId),
          builder: (context, snapshot) {
            final allBranches = snapshot.data ?? const <Branch>[];
            final filtered = allBranches.where((b) {
              final matchesSearch =
                  _search.isEmpty ||
                  b.name.toLowerCase().contains(_search.toLowerCase()) ||
                  (b.code ?? '').toLowerCase().contains(_search.toLowerCase());
              final matchesStatus =
                  _statusFilter == null || b.status == _statusFilter;
              return matchesSearch && matchesStatus;
            }).toList();

            return Scaffold(
              floatingActionButton: canManage
                  ? FloatingActionButton.extended(
                      onPressed: () => _openForm(
                        context,
                        schoolId,
                        tenant.user.userId,
                        allBranches,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add branch'),
                    )
                  : null,
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search branches',
                              isDense: true,
                            ),
                            onChanged: (value) =>
                                setState(() => _search = value),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        DropdownButton<BranchStatus?>(
                          value: _statusFilter,
                          hint: const Text('All statuses'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All statuses'),
                            ),
                            for (final s in BranchStatus.values)
                              DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s == BranchStatus.active
                                      ? 'Active'
                                      : 'Inactive',
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _statusFilter = value),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : ResponsiveDataList<Branch>(
                            items: filtered,
                            columnHeaders: const [
                              'Name',
                              'Code',
                              'City',
                              'Status',
                              '',
                            ],
                            emptyState: const EmptyView(
                              icon: Icons.apartment_outlined,
                              message: 'No branches match your filters.',
                            ),
                            cellsBuilder: (branch) => [
                              DataCell(Text(branch.name)),
                              DataCell(Text(branch.code ?? '—')),
                              DataCell(Text(branch.city ?? '—')),
                              DataCell(_StatusChip(status: branch.status)),
                              DataCell(
                                canManage
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            tooltip: 'Edit',
                                            onPressed: () => _openForm(
                                              context,
                                              schoolId,
                                              tenant.user.userId,
                                              allBranches,
                                              existing: branch,
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              branch.status ==
                                                      BranchStatus.active
                                                  ? Icons.block
                                                  : Icons.check_circle_outline,
                                            ),
                                            tooltip:
                                                branch.status ==
                                                    BranchStatus.active
                                                ? 'Deactivate'
                                                : 'Activate',
                                            onPressed: () => _toggleStatus(
                                              branch,
                                              tenant.user.userId,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                            cardBuilder: (branch) => Card(
                              child: ListTile(
                                title: Text(branch.name),
                                subtitle: Text(
                                  [
                                    if (branch.code != null) branch.code,
                                    if (branch.city != null) branch.city,
                                  ].join(' · '),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _StatusChip(status: branch.status),
                                    if (canManage)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openForm(
                                          context,
                                          schoolId,
                                          tenant.user.userId,
                                          allBranches,
                                          existing: branch,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final BranchStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == BranchStatus.active;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Chip(
      label: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}
