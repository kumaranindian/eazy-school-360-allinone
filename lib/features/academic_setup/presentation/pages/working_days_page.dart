import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
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
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Working Days',
                        style: context.textStyles.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Choose which days of the week this branch treats as working days.',
                        style: context.textStyles.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final day in Weekday.values)
                        SwitchListTile(
                          title: Text(day.displayName),
                          value: current.isWorkingDay[day] ?? false,
                          onChanged: canManage
                              ? (value) => setState(
                                  () => _draft = current.copyWith(day, value),
                                )
                              : null,
                        ),
                      const SizedBox(height: AppSpacing.md),
                      if (canManage)
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
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
                        ),
                    ],
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
