import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../staff/domain/teacher_scope.dart';
import '../../../staff/presentation/providers/teacher_scope_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/layouts/scrollable_header.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
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
  late DateTime _month = DateTime(
    SchoolTime.wallNow().year,
    SchoolTime.wallNow().month,
  );
  LeaveKind _kind = LeaveKind.student;
  String? _classId;
  String? _sectionId;
  String? _selected;
  TeacherSection? _teacherSection;

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

  List<FilterField> _filters(
    List<SchoolClass> classes,
    List<Section> sections,
  ) => [
    FilterField.dropdown<String>(
      label: 'Class',
      value: classes.any((c) => c.classId == _classId) ? _classId : null,
      options: [(null, 'All'), for (final c in classes) (c.classId, c.name)],
      onChanged: (v) => setState(() {
        _classId = v;
        _sectionId = null;
      }),
    ),
    if (_classId != null)
      FilterField.dropdown<String>(
        label: 'Section',
        value: sections.any((s) => s.sectionId == _sectionId)
            ? _sectionId
            : null,
        options: [
          (null, 'All'),
          for (final s in sections) (s.sectionId, s.name),
        ],
        onChanged: (v) => setState(() => _sectionId = v),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final theme = Theme.of(context);
    final canStaff = leave.tenant.can(Permission.viewLeave);
    // A teacher sees students' leave only for a section they are assigned to
    // (the rules refuse a branch-wide window), so the page works on one of
    // their sections instead of the "All classes" view.
    final teacherMode = !canStaff && leave.tenant.role == UserRole.teacher;
    TeacherSection? mySection;
    if (teacherMode) {
      final scope = ref.watch(teacherScopeProvider);
      if (scope.isLoading && !scope.hasValue) {
        return const Center(child: CircularProgressIndicator());
      }
      final sections = scope.value?.sections ?? const <TeacherSection>[];
      if (sections.isEmpty) {
        return EmptyView(
          icon: Icons.event_busy_outlined,
          message: scope.value == null
              ? "Your class access isn't set up yet. Ask your school "
                    'administrator to check your teaching assignments.'
              : 'You have no class assigned yet.',
        );
      }
      mySection = sections.contains(_teacherSection)
          ? _teacherSection
          : sections.first;
    }
    final first = DateTime.utc(_month.year, _month.month, 1);
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final fromKey = AttendanceDate.key(first);
    final toKey = AttendanceDate.key(
      DateTime.utc(_month.year, _month.month, daysInMonth),
    );
    final List<SchoolClass> classes = _kind == LeaveKind.student
        ? ref.watch(classesProvider(leave.yearKey)).value ?? const []
        : const [];
    final List<Section> sections =
        (_kind == LeaveKind.student && _classId != null)
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
      classId: mySection?.classId ?? _classId,
      sectionId: mySection?.sectionId ?? _sectionId,
      subjectId: null,
    );
    final entries = ref.watch(leaveCalendarProvider(key));

    return Column(
      children: [
        ScrollableHeader(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
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
                          ButtonSegment(
                            value: LeaveKind.staff,
                            label: Text('Staff'),
                          ),
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
                  ],
                ),
                if (_kind == LeaveKind.student && mySection != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: DropdownButtonFormField<TeacherSection>(
                      isExpanded: true,
                      value: mySection,
                      decoration: const InputDecoration(
                        labelText: 'My class',
                        isDense: true,
                      ),
                      items: [
                        for (final s
                            in ref
                                    .watch(teacherScopeProvider)
                                    .value
                                    ?.sections ??
                                const <TeacherSection>[])
                          DropdownMenuItem(
                            value: s,
                            child: Text(
                              ref.watch(
                                teacherSectionLabelProvider((
                                  schoolId: leave.schoolId,
                                  branchId: leave.branchId,
                                  section: s,
                                )),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _teacherSection = v;
                        _selected = null;
                      }),
                    ),
                  ),
                ] else if (_kind == LeaveKind.student) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilterBar(fieldsBuilder: () => _filters(classes, sections)),
                ],
              ],
            ),
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
                  const SizedBox(height: AppSpacing.md),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
