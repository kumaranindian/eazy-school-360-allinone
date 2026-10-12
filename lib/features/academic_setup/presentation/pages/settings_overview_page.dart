import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/setup_status_provider.dart';

/// Landing page for `/settings` — the setup checklist (brief §20) plus
/// navigation cards into each sub-section. Distinguishes REQUIRED from
/// OPTIONAL items rather than blocking the app on every item being done.
class SettingsOverviewPage extends ConsumerWidget {
  const SettingsOverviewPage({super.key});

  static const _sections = [
    (
      label: 'School Profile',
      icon: Icons.school_outlined,
      route: AppRoutes.school,
      permission: Permission.manageSchool,
    ),
    (
      label: 'Branches',
      icon: Icons.apartment_outlined,
      route: AppRoutes.settingsBranches,
      permission: Permission.manageBranches,
    ),
    (
      label: 'Academic Years',
      icon: Icons.event_outlined,
      route: AppRoutes.settingsAcademicYears,
      permission: Permission.viewAcademicSetup,
    ),
    (
      label: 'Classes',
      icon: Icons.class_outlined,
      route: AppRoutes.settingsClasses,
      permission: Permission.viewAcademicSetup,
    ),
    (
      label: 'Sections',
      icon: Icons.grid_view_outlined,
      route: AppRoutes.settingsSections,
      permission: Permission.viewAcademicSetup,
    ),
    (
      label: 'Subjects',
      icon: Icons.menu_book_outlined,
      route: AppRoutes.settingsSubjects,
      permission: Permission.viewAcademicSetup,
    ),
    (
      label: 'Working Days',
      icon: Icons.calendar_view_week_outlined,
      route: AppRoutes.settingsWorkingDays,
      permission: Permission.viewAcademicSetup,
    ),
    (
      label: 'Holiday Calendar',
      icon: Icons.event_busy_outlined,
      route: AppRoutes.settingsHolidays,
      permission: Permission.viewAcademicSetup,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.settings_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final statusAsync = ref.watch(
          setupStatusProvider((schoolId: schoolId, branchId: branchId)),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Setup checklist',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              AsyncValueWidget(
                value: statusAsync,
                data: (status) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in status.requiredItems)
                          _ChecklistRow(
                            label: item.label,
                            isComplete: item.isComplete,
                          ),
                        if (status.optionalItems.isNotEmpty) ...[
                          const Divider(height: AppSpacing.lg),
                          Text(
                            'Optional',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          for (final item in status.optionalItems)
                            _ChecklistRow(
                              label: item.label,
                              isComplete: item.isComplete,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Configure', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ResponsiveBuilder(
                builder: (context, screenSize) {
                  final visible = _sections
                      .where((s) => tenant.can(s.permission))
                      .toList();
                  final columns = screenSize.isMobile
                      ? 1
                      : (screenSize.isTablet ? 2 : 3);
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 2.6,
                    children: [
                      for (final section in visible)
                        Card(
                          child: InkWell(
                            onTap: () => context.go(section.route),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Row(
                                children: [
                                  Icon(section.icon),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(child: Text(section.label)),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String label;
  final bool isComplete;

  const _ChecklistRow({required this.label, required this.isComplete});

  @override
  Widget build(BuildContext context) {
    final color = isComplete
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      ),
    );
  }
}
