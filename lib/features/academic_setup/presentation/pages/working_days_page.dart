import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/weekday.dart';
import '../../domain/working_days.dart';
import '../providers/calendar_providers.dart';

class WorkingDaysPage extends ConsumerStatefulWidget {
  const WorkingDaysPage({super.key});

  @override
  ConsumerState<WorkingDaysPage> createState() => _WorkingDaysPageState();
}

class _WorkingDaysPageState extends ConsumerState<WorkingDaysPage> {
  WorkingDays? _draft;

  Future<void> _save(String userId) async {
    final draft = _draft;
    if (draft == null) return;
    final success = await ref
        .read(calendarWriteControllerProvider.notifier)
        .run(
          () => ref
              .read(calendarRepositoryProvider)
              .setWorkingDays(draft, updatedBy: userId),
        );
    if (!mounted) return;
    if (success) {
      context.showSnackBar('Working days updated successfully.');
    } else {
      final error = ref.read(calendarWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to update working days. Please try again.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.calendar_view_week_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageAcademicSetup);
        final workingDaysAsync = ref.watch(
          workingDaysProvider((schoolId: schoolId, branchId: branchId)),
        );
        final isSaving = ref.watch(calendarWriteControllerProvider).isLoading;

        return AsyncValueWidget(
          value: workingDaysAsync,
          data: (loaded) {
            final current = _draft ?? loaded;
            final workingCount = Weekday.values
                .where((d) => current.isWorkingDay[d] ?? false)
                .length;
            return SectionPage(
              title: 'Working days',
              description: 'Which days of the week classes run',
              parentRoute: AppRoutes.settings,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.topLeft,
                  // A short list of switches reads badly stretched across a
                  // wide window; keep it to a comfortable measure.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              child: Text(
                                '$workingCount working '
                                '${workingCount == 1 ? 'day' : 'days'} '
                                'per week',
                                style: context.textStyles.titleSmall,
                              ),
                            ),
                            const Divider(height: 1),
                            for (final day in Weekday.values)
                              SwitchListTile(
                                title: Text(day.displayName),
                                value: current.isWorkingDay[day] ?? false,
                                onChanged: canManage
                                    ? (value) => setState(
                                        () => _draft = current.copyWith(
                                          day,
                                          value,
                                        ),
                                      )
                                    : null,
                              ),
                            if (canManage) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: OverflowBar(
                                  alignment: MainAxisAlignment.end,
                                  spacing: AppSpacing.sm,
                                  overflowSpacing: AppSpacing.sm,
                                  children: [
                                    if (_draft != null && !isSaving)
                                      TextButton(
                                        onPressed: () =>
                                            setState(() => _draft = null),
                                        child: const Text('Discard changes'),
                                      ),
                                    FilledButton(
                                      onPressed: (_draft == null || isSaving)
                                          ? null
                                          : () => _save(tenant.user.userId),
                                      child: isSaving
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Save'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
