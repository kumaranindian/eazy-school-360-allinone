import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../shared/filters/page_actions.dart';
import '../staff_export_action.dart';

/// "Import (CSV)" and "Export (CSV)" buttons for the staff and teacher
/// directories. Export is offered to anyone who can see the list; import
/// only to those who can manage staff (Firestore rules enforce both).
class StaffBulkActions extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final bool teachers;

  const StaffBulkActions({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.teachers,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(tenantContextProvider).value?.can(Permission.manageStaff) ??
        false;
    return Wrap(
      spacing: 8,
      children: [
        if (canManage)
          TextButton.icon(
            onPressed: () => context.push(
              teachers ? '/staff/import?teachers=1' : '/staff/import',
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import (CSV)'),
          ),
        TextButton.icon(
          onPressed: () => exportStaffCsv(
            context,
            ref,
            schoolId: schoolId,
            branchId: branchId,
            teachersOnly: teachers,
          ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export (CSV)'),
        ),
      ],
    );
  }
}

/// Import / Export for the staff and teacher directories as entries of the
/// page's "⋮" menu. Same rules as [StaffBulkActions]: export for anyone who
/// can see the list, import only for those who can manage staff.
List<PageAction> staffBulkPageActions(
  BuildContext context,
  WidgetRef ref, {
  required String schoolId,
  required String branchId,
  required bool teachers,
}) {
  final canManage =
      ref.read(tenantContextProvider).value?.can(Permission.manageStaff) ??
      false;
  return [
    if (canManage)
      PageAction(
        label: 'Import (CSV)',
        icon: Icons.upload_file_outlined,
        onSelected: () => context.push(
          teachers ? '/staff/import?teachers=1' : '/staff/import',
        ),
      ),
    PageAction(
      label: 'Export (CSV)',
      icon: Icons.download_outlined,
      onSelected: () => exportStaffCsv(
        context,
        ref,
        schoolId: schoolId,
        branchId: branchId,
        teachersOnly: teachers,
      ),
    ),
  ];
}
