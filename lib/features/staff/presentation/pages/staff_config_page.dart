import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_branch_scope.dart';
import '../widgets/staff_config_entry.dart';
import '../widgets/staff_config_form_dialog.dart';

/// Departments or designations for a branch — one page for both kinds
/// (they share every field and behaviour). Entries are deactivated, never
/// deleted, so staff records that reference them keep resolving.
class StaffConfigPage extends ConsumerWidget {
  final StaffConfigKind kind;

  const StaffConfigPage({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) {
        final canManage = tenant.can(Permission.manageStaff);
        final key = (schoolId: schoolId, branchId: branchId);
        final entries = switch (kind) {
          StaffConfigKind.department =>
            ref
                .watch(departmentsProvider(key))
                .whenData(
                  (list) => list.map(StaffConfigEntry.fromDepartment).toList(),
                ),
          StaffConfigKind.designation =>
            ref
                .watch(designationsProvider(key))
                .whenData(
                  (list) => list.map(StaffConfigEntry.fromDesignation).toList(),
                ),
        };

        Future<void> openForm({StaffConfigEntry? existing}) async {
          final saved = await showAdaptiveAppDialog<bool>(
            context: context,
            builder: (context) => StaffConfigFormDialog(
              kind: kind,
              schoolId: schoolId,
              branchId: branchId,
              currentUserId: tenant.user.userId,
              existing: existing,
            ),
          );
          if (saved == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${kind.singular} ${existing == null ? 'created' : 'updated'} successfully.',
                ),
              ),
            );
          }
        }

        return Scaffold(
          appBar: AppBar(title: Text(kind.plural)),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => openForm(),
                  icon: const Icon(Icons.add),
                  label: Text('Add ${kind.singular.toLowerCase()}'),
                )
              : null,
          body: AsyncValueWidget(
            value: entries,
            errorMessage: userMessageFor,
            data: (list) => ResponsiveDataList<StaffConfigEntry>(
              items: list,
              columnHeaders: const [
                'Code',
                'Name',
                'Description',
                'Status',
                '',
              ],
              emptyState: EmptyView(
                icon: Icons.account_tree_outlined,
                message:
                    'No ${kind.plural.toLowerCase()} yet.${canManage ? ' Add the first one to start creating staff.' : ''}',
              ),
              cellsBuilder: (entry) => [
                DataCell(Text(entry.code)),
                DataCell(Text(entry.name)),
                DataCell(Text(entry.description ?? '—')),
                DataCell(
                  Text(
                    entry.status == ActivationStatus.active
                        ? 'Active'
                        : 'Inactive',
                  ),
                ),
                DataCell(
                  canManage
                      ? TextButton(
                          onPressed: () => openForm(existing: entry),
                          child: const Text('Edit'),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
              cardBuilder: (entry) => Card(
                child: ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    [
                      entry.code,
                      if (entry.description != null) entry.description!,
                      if (entry.status == ActivationStatus.inactive) 'Inactive',
                    ].join(' · '),
                  ),
                  trailing: canManage ? const Icon(Icons.edit_outlined) : null,
                  onTap: canManage ? () => openForm(existing: entry) : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
