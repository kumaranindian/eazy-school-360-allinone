import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_enums.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';
import '../widgets/leave_widgets.dart';

/// `/leave/calendar` — approved leave by day. Shows who is away and which
/// session, never why: the entries it reads carry no reason, leave type or
/// document. Teachers see students' entries; staff leave is for reviewers.
class LeaveCalendarPage extends StatelessWidget {
  const LeaveCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave calendar')),
      body: LeaveScope(
        showYearSelector: false,
        builder: (context, leave) => _Calendar(leave: leave),
      ),
    );
  }
}

class _Calendar extends ConsumerStatefulWidget {
  final LeaveContext leave;

  const _Calendar({required this.leave});

  @override
  ConsumerState<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends ConsumerState<_Calendar> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  LeaveKind _kind = LeaveKind.student;
  String? _classId;
  String? _sectionId;
  String? _selected;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final theme = Theme.of(context);
    final canStaff = leave.tenant.can(Permission.viewLeave);
    final first = DateTime.utc(_month.year, _month.month, 1);
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final fromKey = AttendanceDate.key(first);
    final toKey = AttendanceDate.key(
      DateTime.utc(_month.year, _month.month, daysInMonth),
    );
    final classes = _kind == LeaveKind.student
        ? ref.watch(classesProvider(leave.yearKey)).value ?? const []
        : const [];
    final sections = (_kind == LeaveKind.student && _classId != null)
        ? ref
                  .watch(
                    sectionsProvider((
                      schoolId: leave.schoolId,
                      branchId: leave.branchId,
                      academicYearId: leave.year.academicYearId,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const []
        : const [];
    final key = (
      schoolId: leave.schoolId,
      branchId: leave.branchId,
      kind: _kind,
      fromKey: fromKey,
      toKey: toKey,
      classId: _classId,
      sectionId: _sectionId,
      subjectId: null,
    );
    final entries = ref.watch(leaveCalendarProvider(key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canStaff)
                SegmentedButton<LeaveKind>(
                  segments: const [
                    ButtonSegment(
                      value: LeaveKind.student,
                      label: Text('Students'),
                    ),
                    ButtonSegment(value: LeaveKind.staff, label: Text('Staff')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _classId = null;
                    _sectionId = null;
                    _selected = null;
                  }),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _month = DateTime(_month.year, _month.month - 1);
                      _selected = null;
                    }),
                  ),
                  Text(
                    '${_months[_month.month - 1]} ${_month.year}',
                    style: theme.textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                      _month = DateTime(_month.year, _month.month + 1);
                      _selected = null;
                    }),
                  ),
                ],
              ),
              if (_kind == LeaveKind.student) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: DropdownButtonFormField<String?>(
                    value: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Class',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      for (final c in classes)
                        DropdownMenuItem(value: c.classId, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _classId = v;
                      _sectionId = null;
                    }),
                  ),
                ),
                if (_classId != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: DropdownButtonFormField<String?>(
                      value: _sectionId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Section',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        for (final s in sections)
                          DropdownMenuItem(
                            value: s.sectionId,
                            child: Text(s.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _sectionId = v),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: entries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(leaveCalendarProvider(key)),
            ),
            data: (list) {
              final byDay = <String, List<LeaveCalendarEntry>>{};
              for (final e in list) {
                for (final d in e.countedDateKeys) {
                  if (d.compareTo(fromKey) >= 0 && d.compareTo(toKey) <= 0) {
                    (byDay[d] ??= []).add(e);
                  }
                }
              }
              final leading = first.weekday - 1; // Monday-first
              final cells = leading + daysInMonth;
              final rows = (cells / 7).ceil();
              final selectedEntries = _selected == null
                  ? const <LeaveCalendarEntry>[]
                  : (byDay[_selected] ?? const []);
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  Row(
                    children: [
                      for (final d in const [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Expanded(
                          child: Center(
                            child: Text(d, style: theme.textTheme.labelSmall),
                          ),
                        ),
                    ],
                  ),
                  for (var r = 0; r < rows; r++)
                    Row(
                      children: [
                        for (var c = 0; c < 7; c++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final day = r * 7 + c - leading + 1;
                                if (day < 1 || day > daysInMonth) {
                                  return const SizedBox(height: 52);
                                }
                                final k = AttendanceDate.key(
                                  DateTime.utc(_month.year, _month.month, day),
                                );
                                final n = byDay[k]?.length ?? 0;
                                final selected = _selected == k;
                                return Semantics(
                                  button: true,
                                  label:
                                      '$day ${_months[_month.month - 1]}, '
                                      '$n on leave',
                                  child: InkWell(
                                    onTap: () => setState(() => _selected = k),
                                    child: Container(
                                      height: 52,
                                      margin: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? theme.colorScheme.primaryContainer
                                            : n > 0
                                            ? theme
                                                  .colorScheme
                                                  .secondaryContainer
                                            : null,
                                        border: Border.all(
                                          color: theme.dividerColor,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      // Fixed-height cell: scale the two
                                      // lines down rather than overflow at
                                      // large text sizes.
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('$day'),
                                            if (n > 0)
                                              Text(
                                                '$n away',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (_selected == null)
                    Text(
                      list.isEmpty
                          ? 'No approved leave in this month.'
                          : 'Select a day to see who is away.',
                      style: theme.textTheme.bodySmall,
                    )
                  else ...[
                    Text(
                      leaveDate(_selected!),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (selectedEntries.isEmpty)
                      const Text('Nobody is on approved leave this day.'),
                    for (final e in selectedEntries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(e.subjectName),
                        subtitle: Text(
                          '${leaveDate(e.startDateKey)} to '
                          '${leaveDate(e.endDateKey)}'
                          '${leaveSession(e.halfDay)}',
                        ),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
