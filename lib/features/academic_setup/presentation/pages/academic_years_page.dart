import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/layouts/section_page.dart';
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

        return SectionPage(
          title: 'Academic years',
          description: 'Terms and the current academic year',
          parentRoute: AppRoutes.settings,
          primaryAction: canManage
              ? SectionAction(
                  label: 'Add academic year',
                  icon: Icons.add,
                  onPressed: () => _openForm(
                    context,
                    schoolId,
                    branchId,
                    tenant.user.userId,
                  ),
                )
              : null,
          child: AsyncValueWidget(
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
  Widget build(BuildContext context) => HubBadge(
    label: status.displayName,
    tone: switch (status) {
      AcademicYearStatus.active => HubBadgeTone.success,
      AcademicYearStatus.draft => HubBadgeTone.neutral,
      AcademicYearStatus.closed => HubBadgeTone.warning,
    },
  );
}
