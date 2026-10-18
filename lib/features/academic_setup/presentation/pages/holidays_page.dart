import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
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

  /// "Remove" keeps the record: the holiday is switched to inactive, so it no
  /// longer closes the school but stays in history (and can be restored by
  /// editing it). Holidays are never deleted.
  Future<void> _remove(Holiday holiday, String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this holiday?'),
        content: Text(
          '"${holiday.name}" will stop closing the school. It stays in the '
          'list as inactive and can be restored by editing it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = Holiday(
      holidayId: holiday.holidayId,
      schoolId: holiday.schoolId,
      branchId: holiday.branchId,
      academicYearId: holiday.academicYearId,
      date: holiday.date,
      endDate: holiday.endDate,
      name: holiday.name,
      type: holiday.type,
      description: holiday.description,
      status: ActivationStatus.inactive,
    );
    String message;
    try {
      await ref
          .read(calendarRepositoryProvider)
          .updateHoliday(removed, updatedBy: userId);
      message = 'Holiday removed.';
    } catch (error) {
      message = userMessageFor(error);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            final workingDays = ref
                .watch(
                  workingDaysProvider((schoolId: schoolId, branchId: branchId)),
                )
                .value;
            final holidaysAsync = ref.watch(
              holidaysProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: yearId,
              )),
            );

            return ResponsiveBuilder(
              builder: (context, screenSize) {
                final effectiveMode = screenSize.isMobile
                    ? _ViewMode.list
                    : _viewMode;
                return SectionPage(
                  title: 'Holidays',
                  description: 'Holidays, festivals and vacations for the year',
                  parentRoute: AppRoutes.settings,
                  primaryAction: canManage
                      ? SectionAction(
                          label: 'Add holiday',
                          icon: Icons.add,
                          onPressed: () => _openForm(
                            context,
                            schoolId,
                            branchId,
                            yearId,
                            tenant.user.userId,
                          ),
                        )
                      : null,
                  toolbar: SectionToolbar(
                    children: [
                      ToolbarField(
                        child: AcademicYearSelector(
                          years: years,
                          selectedId: yearId,
                          onChanged: (id) =>
                              setState(() => _selectedYearId = id),
                        ),
                      ),
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
                  child: AsyncValueWidget(
                    value: holidaysAsync,
                    data: (holidays) {
                      if (effectiveMode == _ViewMode.calendar) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: HolidayCalendarView(
                            holidays: holidays,
                            workingDays: workingDays,
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

                      final today = SchoolTime.wallNow();
                      final upcoming = holidays
                          .where(
                            (h) => !h.lastDate.isBefore(
                              DateTime.utc(today.year, today.month, today.day),
                            ),
                          )
                          .toList();
                      final past = holidays
                          .where(
                            (h) => h.lastDate.isBefore(
                              DateTime.utc(today.year, today.month, today.day),
                            ),
                          )
                          .toList();

                      return ListView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        children: [
                          if (upcoming.isNotEmpty) ...[
                            Text(
                              'Upcoming',
                              style: Theme.of(context).textTheme.titleSmall,
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
                                onRemove: () =>
                                    _remove(holiday, tenant.user.userId),
                              ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          if (past.isNotEmpty) ...[
                            Text(
                              'Past',
                              style: Theme.of(context).textTheme.titleSmall,
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
                                onRemove: () =>
                                    _remove(holiday, tenant.user.userId),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                );
              },
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
  final VoidCallback onRemove;

  const _HolidayTile({
    required this.holiday,
    required this.canManage,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          holiday.status == ActivationStatus.active
              ? holiday.name
              : '${holiday.name} (inactive)',
          style: holiday.status == ActivationStatus.active
              ? null
              : TextStyle(color: Theme.of(context).disabledColor),
        ),
        subtitle: Text(
          '${formatDisplayDate(holiday.date)}'
          '${holiday.isRange ? ' – ${formatDisplayDate(holiday.lastDate)} · ${holiday.dayCount} days' : ''}'
          ' · ${holiday.type.displayName}',
        ),
        trailing: canManage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  if (holiday.status == ActivationStatus.active)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onRemove,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
