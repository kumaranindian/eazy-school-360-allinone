import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/academic_year.dart';
import '../../domain/academic_year_status.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/academic_year_form_dialog.dart';

class AcademicYearsPage extends ConsumerWidget {
  const AcademicYearsPage({super.key});

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String userId, {
    AcademicYear? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => AcademicYearFormDialog(
        schoolId: schoolId,
        branchId: branchId,
        currentUserId: userId,
        existing: existing,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Academic year created.'
                : 'Academic year updated.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageAcademicSetup);
        final yearsAsync = ref.watch(
          academicYearsProvider((schoolId: schoolId, branchId: branchId)),
        );

        return Scaffold(
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _openForm(
                    context,
                    schoolId,
                    branchId,
                    tenant.user.userId,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add academic year'),
                )
              : null,
          body: AsyncValueWidget(
            value: yearsAsync,
            data: (years) => ResponsiveDataList<AcademicYear>(
              items: years,
              columnHeaders: const ['Name', 'Start', 'End', 'Status', ''],
              emptyState: const EmptyView(
                icon: Icons.event_outlined,
                message:
                    'No academic years yet. Add one to start configuring classes and subjects.',
              ),
              cellsBuilder: (year) => [
                DataCell(Text(year.name)),
                DataCell(Text(formatDisplayDate(year.startDate))),
                DataCell(Text(formatDisplayDate(year.endDate))),
                DataCell(_StatusChip(status: year.status)),
                DataCell(
                  canManage
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => _openForm(
                            context,
                            schoolId,
                            branchId,
                            tenant.user.userId,
                            existing: year,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
              cardBuilder: (year) => Card(
                child: ListTile(
                  title: Text(year.name),
                  subtitle: Text(
                    '${formatDisplayDate(year.startDate)} - ${formatDisplayDate(year.endDate)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusChip(status: year.status),
                      if (canManage)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openForm(
                            context,
                            schoolId,
                            branchId,
                            tenant.user.userId,
                            existing: year,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AcademicYearStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AcademicYearStatus.active => Theme.of(context).colorScheme.primary,
      AcademicYearStatus.draft => Theme.of(context).colorScheme.outline,
      AcademicYearStatus.closed => Theme.of(context).colorScheme.error,
    };
    return Chip(
      label: Text(
        status.displayName,
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    );
  }
}
