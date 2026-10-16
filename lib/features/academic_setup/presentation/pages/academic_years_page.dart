import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
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
import '../../domain/school_academic_year.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/academic_year_form_dialog.dart';
import '../widgets/school_year_dialogs.dart';

class AcademicYearsPage extends ConsumerWidget {
  const AcademicYearsPage({super.key});

  Future<void> _openYear(
    BuildContext context,
    WidgetRef ref,
    String schoolId,
    String branchId,
    String userId,
    List<AcademicYear> years,
    List<SchoolAcademicYear> registry,
  ) async {
    final openable = SchoolYearRules.openableIn(registry, [
      for (final y in years) y.academicYearId,
    ]);
    final opened = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (_) => OpenSchoolYearDialog(
        schoolId: schoolId,
        branchId: branchId,
        userId: userId,
        openable: openable,
      ),
    );
    if (opened == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Academic year opened as a draft.')),
      );
    }
  }

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String userId, {
    required AcademicYear existing,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Academic year updated.')));
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
        // Kept alive here so the "Open a school year" list is ready on tap.
        final registryAsync = ref.watch(schoolYearsProvider(schoolId));

        return SectionPage(
          title: 'Academic years',
          description: 'Terms and the current academic year',
          parentRoute: AppRoutes.settings,
          primaryAction: canManage
              ? SectionAction(
                  label: 'Open a school year',
                  icon: Icons.lock_open_outlined,
                  onPressed: () => _openYear(
                    context,
                    ref,
                    schoolId,
                    branchId,
                    tenant.user.userId,
                    yearsAsync.value ?? const [],
                    registryAsync.value ?? const [],
                  ),
                )
              : null,
          toolbar: tenant.user.homeRole == UserRole.schoolAdmin
              ? TextButton.icon(
                  onPressed: () => context.go(AppRoutes.settingsSchoolYears),
                  icon: const Icon(Icons.public_outlined),
                  label: const Text('School years (all branches)'),
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
                    'No academic years open in this branch yet. Open a school year to start configuring classes and subjects.',
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
