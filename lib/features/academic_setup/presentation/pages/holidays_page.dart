import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/holiday.dart';
import '../providers/calendar_providers.dart';
import '../widgets/academic_year_selector.dart';
import '../widgets/holiday_calendar_view.dart';
import '../widgets/holiday_form_dialog.dart';
import '../providers/academic_structure_providers.dart';

enum _ViewMode { calendar, list }

class HolidaysPage extends ConsumerStatefulWidget {
  const HolidaysPage({super.key});

  @override
  ConsumerState<HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends ConsumerState<HolidaysPage> {
  String? _selectedYearId;
  _ViewMode _viewMode = _ViewMode.list;

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String yearId,
    String userId, {
    Holiday? existing,
    DateTime? initialDate,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => HolidayFormDialog(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: yearId,
        currentUserId: userId,
        existing: existing,
        initialDate: initialDate,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Holiday added.' : 'Holiday updated.',
          ),
        ),
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
            icon: Icons.event_busy_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageAcademicSetup);
        final yearsAsync = ref.watch(
          academicYearsProvider((schoolId: schoolId, branchId: branchId)),
        );

        return AsyncValueWidget(
          value: yearsAsync,
          data: (years) {
            if (years.isEmpty) {
              return const EmptyView(
                icon: Icons.event_busy_outlined,
                message: 'Add an academic year first.',
              );
            }
            final yearId = years.any((y) => y.academicYearId == _selectedYearId)
                ? _selectedYearId!
                : years.first.academicYearId;
            final holidaysAsync = ref.watch(
              holidaysProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: yearId,
              )),
            );

            return Scaffold(
              floatingActionButton: canManage
                  ? FloatingActionButton.extended(
                      onPressed: () => _openForm(
                        context,
                        schoolId,
                        branchId,
                        yearId,
                        tenant.user.userId,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add holiday'),
                    )
                  : null,
              body: ResponsiveBuilder(
                builder: (context, screenSize) {
                  final effectiveMode = screenSize.isMobile
                      ? _ViewMode.list
                      : _viewMode;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 220,
                              child: AcademicYearSelector(
                                years: years,
                                selectedId: yearId,
                                onChanged: (id) =>
                                    setState(() => _selectedYearId = id),
                              ),
                            ),
                            const Spacer(),
                            if (!screenSize.isMobile)
                              SegmentedButton<_ViewMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: _ViewMode.list,
                                    icon: Icon(Icons.list),
                                    label: Text('List'),
                                  ),
                                  ButtonSegment(
                                    value: _ViewMode.calendar,
                                    icon: Icon(Icons.calendar_month),
                                    label: Text('Calendar'),
                                  ),
                                ],
                                selected: {effectiveMode},
                                onSelectionChanged: (selection) =>
                                    setState(() => _viewMode = selection.first),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: AsyncValueWidget(
                          value: holidaysAsync,
                          data: (holidays) {
                            if (effectiveMode == _ViewMode.calendar) {
                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: HolidayCalendarView(
                                  holidays: holidays,
                                  onDayTap: canManage
                                      ? (date, existing) => _openForm(
                                          context,
                                          schoolId,
                                          branchId,
                                          yearId,
                                          tenant.user.userId,
                                          existing: existing,
                                          initialDate: date,
                                        )
                                      : (date, existing) {},
                                ),
                              );
                            }

                            if (holidays.isEmpty) {
                              return const EmptyView(
                                icon: Icons.event_busy_outlined,
                                message:
                                    'No holidays recorded for this academic year yet.',
                              );
                            }

                            final today = DateTime.now();
                            final upcoming = holidays
                                .where(
                                  (h) => !h.date.isBefore(
                                    DateTime(
                                      today.year,
                                      today.month,
                                      today.day,
                                    ),
                                  ),
                                )
                                .toList();
                            final past = holidays
                                .where(
                                  (h) => h.date.isBefore(
                                    DateTime(
                                      today.year,
                                      today.month,
                                      today.day,
                                    ),
                                  ),
                                )
                                .toList();

                            return ListView(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              children: [
                                if (upcoming.isNotEmpty) ...[
                                  Text(
                                    'Upcoming',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  for (final holiday in upcoming)
                                    _HolidayTile(
                                      holiday: holiday,
                                      canManage: canManage,
                                      onEdit: () => _openForm(
                                        context,
                                        schoolId,
                                        branchId,
                                        yearId,
                                        tenant.user.userId,
                                        existing: holiday,
                                      ),
                                    ),
                                  const SizedBox(height: AppSpacing.md),
                                ],
                                if (past.isNotEmpty) ...[
                                  Text(
                                    'Past',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  for (final holiday in past)
                                    _HolidayTile(
                                      holiday: holiday,
                                      canManage: canManage,
                                      onEdit: () => _openForm(
                                        context,
                                        schoolId,
                                        branchId,
                                        yearId,
                                        tenant.user.userId,
                                        existing: holiday,
                                      ),
                                    ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _HolidayTile extends StatelessWidget {
  final Holiday holiday;
  final bool canManage;
  final VoidCallback onEdit;

  const _HolidayTile({
    required this.holiday,
    required this.canManage,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(holiday.name),
        subtitle: Text(
          '${formatDisplayDate(holiday.date)} · ${holiday.type.displayName}',
        ),
        trailing: canManage
            ? IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              )
            : null,
      ),
    );
  }
}
