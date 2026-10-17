import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/weekday.dart';
import '../../domain/weekly_pattern.dart';
import '../../domain/working_days.dart';
import '../providers/calendar_providers.dart';

/// How Saturday is configured in the form. "Alternate" and "selected" both end
/// up as a set of off-weeks; "every Saturday" switches Saturday off entirely,
/// which is why the week choices are hidden then (nothing left to configure).
enum _SaturdayMode { working, off, alternate, selected }

class _Draft {
  final Map<Weekday, bool> days;
  final _SaturdayMode mode;
  final bool alternateOdd;
  final Set<int> selectedWeeks;
  final DateTime? startsOn;

  const _Draft({
    required this.days,
    required this.mode,
    required this.alternateOdd,
    required this.selectedWeeks,
    required this.startsOn,
  });

  factory _Draft.from(WorkingDays w) {
    final policy = w.saturdayPolicy;
    return _Draft(
      days: {...w.isWorkingDay},
      mode: switch (policy) {
        SaturdayPolicy.allWorking => _SaturdayMode.working,
        SaturdayPolicy.allOff => _SaturdayMode.off,
        SaturdayPolicy.alternateOdd ||
        SaturdayPolicy.alternateEven => _SaturdayMode.alternate,
        SaturdayPolicy.selected => _SaturdayMode.selected,
      },
      alternateOdd: policy != SaturdayPolicy.alternateEven,
      selectedWeeks: {...w.saturdayOffWeeks},
      startsOn: null,
    );
  }

  _Draft copyWith({
    Map<Weekday, bool>? days,
    _SaturdayMode? mode,
    bool? alternateOdd,
    Set<int>? selectedWeeks,
    DateTime? startsOn,
  }) => _Draft(
    days: days ?? this.days,
    mode: mode ?? this.mode,
    alternateOdd: alternateOdd ?? this.alternateOdd,
    selectedWeeks: selectedWeeks ?? this.selectedWeeks,
    startsOn: startsOn ?? this.startsOn,
  );

  /// The Saturday off-weeks this draft means (empty unless some, not all).
  Set<int> get offWeeks => switch (mode) {
    _SaturdayMode.working || _SaturdayMode.off => const {},
    _SaturdayMode.alternate => alternateOdd ? const {1, 3, 5} : const {2, 4},
    _SaturdayMode.selected => selectedWeeks,
  };

  /// The flags to store: Saturday is off only for "every Saturday".
  Map<Weekday, bool> get flags => {
    ...days,
    Weekday.saturday: mode != _SaturdayMode.off,
  };

  WeeklyPattern get pattern =>
      WeeklyPattern(isWorkingDay: flags, saturdayOffWeeks: offWeeks);

  /// Whether the weekly rhythm is the same (the start date alone is not a
  /// change worth saving).
  bool sameAs(_Draft other) => pattern.sameRhythmAs(other.pattern);
}

/// `Settings -> Weekly offs`: which weekdays are off, how Saturdays work, and
/// from which date the change applies. Holidays (single days and vacations)
/// are on the Holidays page; both feed the same [SchoolCalendar].
class WorkingDaysPage extends ConsumerStatefulWidget {
  const WorkingDaysPage({super.key});

  @override
  ConsumerState<WorkingDaysPage> createState() => _WorkingDaysPageState();
}

class _WorkingDaysPageState extends ConsumerState<WorkingDaysPage> {
  _Draft? _draft;

  Future<void> _pickStart(_Draft current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.startsOn ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'New weekly offs start on',
    );
    if (picked != null) {
      setState(
        () => _draft = current.copyWith(
          startsOn: DateTime(picked.year, picked.month, picked.day),
        ),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes to the weekly offs. They will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _save({
    required String userId,
    required WorkingDays loaded,
    required bool configured,
    required _Draft draft,
  }) async {
    final startsOn = draft.startsOn ?? DateTime.now();
    final startKey = WorkingDays.keyOf(startsOn);
    if (draft.mode == _SaturdayMode.selected && draft.selectedWeeks.isEmpty) {
      context.showSnackBar(
        'Choose at least one Saturday, or pick "No Saturday holidays".',
        isError: true,
      );
      return;
    }
    if (configured) {
      final problem = loaded.checkEffectiveFrom(startKey);
      if (problem != null) {
        context.showSnackBar(problem, isError: true);
        return;
      }
    }
    final next = loaded.scheduleChange(
      pattern: draft.flags,
      saturdayOffWeeks: draft.offWeeks,
      startsOn: startKey,
      configuredBefore: configured,
    );
    final success = await ref
        .read(calendarWriteControllerProvider.notifier)
        .run(
          () => ref
              .read(calendarRepositoryProvider)
              .setWorkingDays(next, updatedBy: userId),
        );
    if (!mounted) return;
    if (success) {
      setState(() => _draft = null);
      ref.invalidate(workingDaysProvider);
      context.showSnackBar(
        configured
            ? 'Weekly offs saved. They apply from ${formatDisplayDate(startsOn)}; '
                  'earlier dates keep the pattern they had.'
            : 'Weekly offs saved.',
      );
    } else {
      final error = ref.read(calendarWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save the weekly offs. Please try again.'
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
            final saved = _Draft.from(loaded);
            final draft = _draft ?? saved;
            final dirty = _draft != null && !_draft!.sameAs(saved);
            // A branch that has never saved a pattern shows today's defaults;
            // its first save applies from the start (nothing to preserve).
            final configured =
                loaded.updatedAt != null || loaded.updatedBy != null;
            final theme = Theme.of(context);

            void edit(_Draft next) => setState(() => _draft = next);

            return PopScope(
              canPop: !dirty,
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop) return;
                final leave = await _confirmDiscard();
                if (leave && context.mounted) {
                  setState(() => _draft = null);
                  Navigator.of(context).maybePop();
                }
              },
              child: SectionPage(
                title: 'Weekly offs',
                description: 'Which days of the week are holidays',
                parentRoute: AppRoutes.settings,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Weekly offs',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    draft.pattern.summary,
                                    key: const ValueKey('weeklyOffSummary'),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    AppSpacing.md,
                                    AppSpacing.md,
                                    AppSpacing.xs,
                                  ),
                                  child: Text(
                                    'Weekdays (switch on = a working day)',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                for (final day in Weekday.values)
                                  if (day != Weekday.saturday)
                                    SwitchListTile(
                                      key: ValueKey('day-${day.name}'),
                                      title: Text(day.displayName),
                                      value: draft.days[day] ?? false,
                                      onChanged: canManage
                                          ? (v) => edit(
                                              draft.copyWith(
                                                days: {...draft.days, day: v},
                                              ),
                                            )
                                          : null,
                                    ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    0,
                                    AppSpacing.md,
                                    AppSpacing.sm,
                                  ),
                                  child: Text(
                                    'Saturdays are set below.',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                    ),
                                    child: Text(
                                      'Saturdays',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  _modeTile(
                                    draft,
                                    edit,
                                    canManage,
                                    _SaturdayMode.working,
                                    'No Saturday holidays',
                                    'Every Saturday is a working day.',
                                  ),
                                  _modeTile(
                                    draft,
                                    edit,
                                    canManage,
                                    _SaturdayMode.off,
                                    'Every Saturday is a holiday',
                                    'Nothing else to choose.',
                                  ),
                                  _modeTile(
                                    draft,
                                    edit,
                                    canManage,
                                    _SaturdayMode.alternate,
                                    'Alternate Saturdays',
                                    'Every other Saturday is a holiday.',
                                  ),
                                  if (draft.mode == _SaturdayMode.alternate)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.xl,
                                        0,
                                        AppSpacing.md,
                                        AppSpacing.sm,
                                      ),
                                      child: SegmentedButton<bool>(
                                        key: const ValueKey('alternate'),
                                        segments: const [
                                          ButtonSegment(
                                            value: true,
                                            label: Text('1st, 3rd, 5th'),
                                          ),
                                          ButtonSegment(
                                            value: false,
                                            label: Text('2nd, 4th'),
                                          ),
                                        ],
                                        selected: {draft.alternateOdd},
                                        onSelectionChanged: canManage
                                            ? (s) => edit(
                                                draft.copyWith(
                                                  alternateOdd: s.first,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  _modeTile(
                                    draft,
                                    edit,
                                    canManage,
                                    _SaturdayMode.selected,
                                    'Selected Saturdays',
                                    'Choose exactly which Saturdays of the '
                                        'month are holidays.',
                                  ),
                                  if (draft.mode == _SaturdayMode.selected)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.xl,
                                        0,
                                        AppSpacing.md,
                                        AppSpacing.sm,
                                      ),
                                      child: Wrap(
                                        spacing: AppSpacing.sm,
                                        runSpacing: AppSpacing.xs,
                                        children: [
                                          for (var n = 1; n <= 5; n++)
                                            FilterChip(
                                              key: ValueKey('week-$n'),
                                              label: Text(
                                                '${WeeklyPattern.ordinal(n)} Saturday',
                                              ),
                                              selected: draft.selectedWeeks
                                                  .contains(n),
                                              onSelected: canManage
                                                  ? (on) => edit(
                                                      draft.copyWith(
                                                        selectedWeeks: {
                                                          ...draft
                                                              .selectedWeeks,
                                                        }..addOrRemove(n, on),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                        ],
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.md,
                                      AppSpacing.xs,
                                      AppSpacing.md,
                                      AppSpacing.xs,
                                    ),
                                    child: Text(
                                      'A 5th-Saturday rule applies only in '
                                      'months that have a 5th Saturday.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (configured) ...[
                            const SizedBox(height: AppSpacing.md),
                            Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Takes effect from',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    OutlinedButton.icon(
                                      key: const ValueKey('startsOn'),
                                      onPressed: canManage
                                          ? () => _pickStart(draft)
                                          : null,
                                      icon: const Icon(Icons.event),
                                      label: Text(
                                        formatDisplayDate(
                                          draft.startsOn ?? DateTime.now(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Dates before this day keep the weekly '
                                      'offs they already had, so attendance and '
                                      'leave already recorded are not changed. '
                                      'Currently in force from '
                                      '${loaded.effectiveFrom == null ? 'the beginning' : formatDisplayDate(DateTime.parse(loaded.effectiveFrom!))}'
                                      '.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (canManage) ...[
                            const SizedBox(height: AppSpacing.md),
                            OverflowBar(
                              alignment: MainAxisAlignment.end,
                              spacing: AppSpacing.sm,
                              overflowSpacing: AppSpacing.sm,
                              children: [
                                TextButton(
                                  onPressed: (dirty && !isSaving)
                                      ? () => setState(() => _draft = null)
                                      : null,
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: (!dirty || isSaving)
                                      ? null
                                      : () => _save(
                                          userId: tenant.user.userId,
                                          loaded: loaded,
                                          configured: configured,
                                          draft: draft,
                                        ),
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
                          ],
                        ],
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

  Widget _modeTile(
    _Draft draft,
    void Function(_Draft) edit,
    bool canManage,
    _SaturdayMode mode,
    String title,
    String subtitle,
  ) {
    return RadioListTile<_SaturdayMode>(
      key: ValueKey('sat-${mode.name}'),
      title: Text(title),
      subtitle: Text(subtitle),
      value: mode,
      groupValue: draft.mode,
      onChanged: canManage ? (m) => edit(draft.copyWith(mode: m)) : null,
    );
  }
}

extension on Set<int> {
  void addOrRemove(int value, bool add) =>
      add ? this.add(value) : remove(value);
}
