import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../school_setup/domain/branch.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/school_academic_year.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/school_year_dialogs.dart';

/// `/settings/academic-years/school` — the school-wide academic years and which
/// branches have opened each. School admin only.
class SchoolYearsPage extends ConsumerWidget {
  const SchoolYearsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        if (tenant == null ||
            schoolId == null ||
            tenant.user.homeRole != UserRole.schoolAdmin) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message: 'Only a school administrator can manage school years.',
          );
        }
        final years = ref.watch(schoolYearsProvider(schoolId));
        final branches =
            ref.watch(schoolBranchesProvider(schoolId)).value ?? const [];
        return SectionPage(
          title: 'School years',
          description: 'Academic years for the whole school',
          parentRoute: AppRoutes.settingsAcademicYears,
          parentLabel: 'Academic years',
          primaryAction: SectionAction(
            label: 'Add school year',
            icon: Icons.add,
            onPressed: () async {
              final names = [
                for (final y in years.value ?? const <SchoolAcademicYear>[])
                  y.name,
              ];
              final saved = await showAdaptiveAppDialog<bool>(
                context: context,
                builder: (_) => SchoolYearFormDialog(
                  schoolId: schoolId,
                  userId: tenant.user.userId,
                  existingNames: names,
                ),
              );
              if (saved == true && context.mounted) {
                context.showSnackBar('School year added. Open it in branches.');
              }
            },
          ),
          child: AsyncValueWidget(
            value: years,
            data: (list) => list.isEmpty
                ? const EmptyView(
                    icon: Icons.event_outlined,
                    message:
                        'No school years yet. Add one, then open it in each branch.',
                  )
                : ListView(
                    children: [
                      for (final y in list)
                        _YearCard(
                          year: y,
                          branches: branches,
                          userId: tenant.user.userId,
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _YearCard extends ConsumerWidget {
  final SchoolAcademicYear year;
  final List<Branch> branches;
  final String userId;
  const _YearCard({
    required this.year,
    required this.branches,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ids = [for (final b in branches) b.branchId];
    final opened = ref.watch(
      schoolYearOpenedProvider((
        schoolId: year.schoolId,
        yearId: year.schoolYearId,
        branchIds: ids.join(','),
      )),
    );
    final openedSet = opened.value ?? const <String>{};

    Future<void> openIn() async {
      final done = await showAdaptiveAppDialog<bool>(
        context: context,
        builder: (_) => OpenInBranchesDialog(
          year: year,
          branches: branches,
          alreadyOpen: openedSet,
          userId: userId,
        ),
      );
      if (done == true) {
        ref.invalidate(schoolYearOpenedProvider);
        if (context.mounted) context.showSnackBar('Opened.');
      }
    }

    Future<void> toggleArchive() async {
      try {
        await ref
            .read(schoolYearRepositoryProvider)
            .setArchived(
              year.schoolId,
              year.schoolYearId,
              archived: year.isOpenable,
              updatedBy: userId,
            );
      } catch (e) {
        if (context.mounted) {
          context.showSnackBar(userMessageFor(e), isError: true);
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(year.name, style: theme.textTheme.titleMedium),
                ),
                HubBadge(
                  label: year.status.label,
                  tone: year.isOpenable
                      ? HubBadgeTone.success
                      : HubBadgeTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatDisplayDate(year.startDate)} – ${formatDisplayDate(year.endDate)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              opened.isLoading
                  ? 'Checking branches…'
                  : 'Open in ${openedSet.length} of ${branches.length} branches',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (year.isOpenable && openedSet.length < branches.length)
                  FilledButton.tonalIcon(
                    onPressed: opened.isLoading ? null : openIn,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Open in branches'),
                  ),
                OutlinedButton.icon(
                  onPressed: toggleArchive,
                  icon: Icon(
                    year.isOpenable
                        ? Icons.archive_outlined
                        : Icons.unarchive_outlined,
                  ),
                  label: Text(year.isOpenable ? 'Archive' : 'Restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
