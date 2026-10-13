import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/domain/weekday.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../../shared/layouts/scope_bar.dart';
import '../../domain/substitution.dart';
import '../../domain/timetable_validation.dart';
import '../providers/timetable_providers.dart';
import '../widgets/timetable_format.dart';
import '../widgets/timetable_scope.dart';
import '../widgets/week_agenda.dart';

/// Builds the week as agenda items from bundles, for the date's week, with
/// date-specific substitutions layered over the regular timetable.
Map<Weekday, List<AgendaItem>> buildWeek({
  required List<TimetableBundle> bundles,
  required String mondayKey,
  required List<Substitution> substitutions,
  String? onlyTeacherId,
  required bool showClass,
  required bool showTeacher,
  String? coveringTeacherId,
}) {
  final result = <Weekday, List<AgendaItem>>{};
  final monday = AttendanceDate.parse(mondayKey);
  final published = bundles.map((b) => b.timetable).toList();
  final byTimetable = {for (final b in bundles) b.timetable.timetableId: b};
  final subs = {
    for (final s in substitutions)
      if (s.isActive) s.substitutionId: s,
  };
  for (var i = 0; i < 7; i++) {
    final date = DateTime.utc(monday.year, monday.month, monday.day + i);
    final key = AttendanceDate.key(date);
    final wd = Weekday.fromDateTimeWeekday(date.weekday);
    final items = <(int, AgendaItem)>[];
    for (final t in TimetableResolver.allOn(published, key)) {
      for (final e in byTimetable[t.timetableId]!.entries) {
        if (e.weekday != wd) continue;
        final sub = subs[Substitution.idFor(key, t.timetableId, e.slotId)];
        if (onlyTeacherId != null) {
          // the teacher's own regular periods (unless covered by someone
          // else) and the periods they cover that day
          final mine = e.teacherStaffId == onlyTeacherId;
          final covering =
              sub != null && sub.substituteTeacherId == onlyTeacherId;
          if (!mine && !covering) continue;
          if (mine && sub != null && !covering) {
            items.add((
              e.startMin,
              AgendaItem(
                time: 'Period ${e.periodNumber} · ${e.timeLabel}',
                title: '${e.subjectName} · ${t.title}',
                subtitle: 'Covered by ${sub.substituteTeacherName}',
                isEmpty: true,
              ),
            ));
            continue;
          }
          items.add((
            e.startMin,
            AgendaItem(
              time: 'Period ${e.periodNumber} · ${e.timeLabel}',
              title: '${e.subjectName} · ${t.title}',
              subtitle: e.room == null ? null : 'Room ${e.room}',
              badge: covering
                  ? 'You are covering for ${sub.originalTeacherName}'
                  : null,
              highlight: covering,
            ),
          ));
          continue;
        }
        items.add((
          e.startMin,
          AgendaItem(
            time: 'Period ${e.periodNumber} · ${e.timeLabel}',
            title: e.subjectName,
            subtitle: [
              if (showTeacher)
                sub != null ? sub.substituteTeacherName : e.teacherName,
              if (showClass) t.title,
              if (e.room != null) 'Room ${e.room}',
            ].join(' · '),
            badge: sub == null
                ? null
                : 'Substitute for ${sub.originalTeacherName}',
            highlight: sub != null,
          ),
        ));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    (result[wd] ??= []).addAll([for (final x in items) x.$2]);
  }
  return result;
}

String mondayOf(DateTime d) {
  final date = DateTime.utc(d.year, d.month, d.day);
  final monday = DateTime.utc(
    date.year,
    date.month,
    date.day - (date.weekday - 1),
  );
  return AttendanceDate.key(monday);
}

List<Weekday> _usedDays(Map<Weekday, List<AgendaItem>> items) => [
  for (final d in Weekday.values)
    if ((items[d] ?? const []).isNotEmpty) d,
];

// ------------------------------------------------------------ class / section

/// `/timetable/view` — one section's timetable for a chosen week, with that
/// week's substitutions shown over it. The regular timetable is never edited.
class SectionTimetablePage extends StatelessWidget {
  const SectionTimetablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class timetable')),
      body: TimetableScope(builder: (context, tt) => _Section(tt: tt)),
    );
  }
}

class _Section extends ConsumerStatefulWidget {
  final TimetableContext tt;

  const _Section({required this.tt});

  @override
  ConsumerState<_Section> createState() => _SectionState();
}

class _SectionState extends ConsumerState<_Section> {
  String? _classId;
  String? _sectionId;
  String _monday = mondayOf(DateTime.now());

  void _shift(int weeks) {
    final m = AttendanceDate.parse(_monday);
    setState(
      () => _monday = AttendanceDate.key(
        DateTime.utc(m.year, m.month, m.day + 7 * weeks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final classes =
        ref.watch(classesProvider(tt.academicKey)).value ?? const [];
    final sections = _classId == null
        ? const []
        : ref
                  .watch(
                    sectionsProvider((
                      schoolId: tt.schoolId,
                      branchId: tt.branchId,
                      academicYearId: tt.year.academicYearId,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ScopeBar(
            complete: _classId != null && _sectionId != null,
            summary: _classId == null || _sectionId == null
                ? 'Choose a class and section'
                : '${classes.where((c) => c.classId == _classId).firstOrNull?.name ?? 'Class'} · '
                      '${sections.where((x) => x.sectionId == _sectionId).firstOrNull?.name ?? ''} · '
                      'Week of ${ttDate(_monday)}',
            controlsBuilder: (context, narrow) => Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: narrow ? double.infinity : 180,
                  child: DropdownButtonFormField<String>(
                    value: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Class',
                      isDense: true,
                    ),
                    items: [
                      for (final c in classes)
                        DropdownMenuItem(value: c.classId, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _classId = v;
                      _sectionId = null;
                    }),
                  ),
                ),
                SizedBox(
                  width: narrow ? double.infinity : 160,
                  child: DropdownButtonFormField<String>(
                    value: _sectionId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Section',
                      isDense: true,
                    ),
                    items: [
                      for (final s in sections)
                        DropdownMenuItem(
                          value: s.sectionId,
                          child: Text(s.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _sectionId = v),
                  ),
                ),
                WeekNavigator(
                  label: 'Week of ${ttDate(_monday)}',
                  onShift: _shift,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _classId == null || _sectionId == null
              ? const EmptyView(
                  icon: Icons.calendar_view_week_outlined,
                  message: 'Choose a class and section.',
                )
              : SectionWeek(
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                  academicYearId: tt.year.academicYearId,
                  classId: _classId!,
                  sectionId: _sectionId!,
                  mondayKey: _monday,
                ),
        ),
      ],
    );
  }
}

/// A section's week (shared by admins and the parent view).
class SectionWeek extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String mondayKey;

  const SectionWeek({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    required this.mondayKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      classId: classId,
      sectionId: sectionId,
    );
    final bundles = ref.watch(sectionBundlesProvider(key));
    final monday = AttendanceDate.parse(mondayKey);
    final sunday = AttendanceDate.key(
      DateTime.utc(monday.year, monday.month, monday.day + 6),
    );
    final subs = ref.watch(
      sectionSubstitutionsProvider((
        schoolId: schoolId,
        branchId: branchId,
        classId: classId,
        sectionId: sectionId,
        fromKey: mondayKey,
        toKey: sunday,
      )),
    );
    return bundles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(sectionBundlesProvider(key)),
      ),
      data: (list) {
        final items = buildWeek(
          bundles: list,
          mondayKey: mondayKey,
          substitutions: subs.value ?? const [],
          showClass: false,
          showTeacher: true,
        );
        final days = _usedDays(items);
        if (days.isEmpty) {
          return const EmptyView(
            icon: Icons.event_busy_outlined,
            message: 'No published timetable is in force for this week.',
          );
        }
        return WeekAgenda(days: days, items: items);
      },
    );
  }
}

typedef SectionSubstitutionsKey = ({
  String schoolId,
  String branchId,
  String classId,
  String sectionId,
  String fromKey,
  String toKey,
});

final sectionSubstitutionsProvider = FutureProvider.autoDispose
    .family<List<Substitution>, SectionSubstitutionsKey>((ref, key) {
      return ref
          .watch(substitutionRepositoryProvider)
          .fetchForSection(
            schoolId: key.schoolId,
            branchId: key.branchId,
            classId: key.classId,
            sectionId: key.sectionId,
            fromKey: key.fromKey,
            toKey: key.toKey,
          );
    });

typedef TeacherSubstitutionsKey = ({
  String schoolId,
  String branchId,
  String teacherStaffId,
  String fromKey,
  String toKey,
});

final teacherSubstitutionsProvider = FutureProvider.autoDispose
    .family<List<Substitution>, TeacherSubstitutionsKey>((ref, key) {
      return ref
          .watch(substitutionRepositoryProvider)
          .fetchForTeacher(
            schoolId: key.schoolId,
            branchId: key.branchId,
            teacherStaffId: key.teacherStaffId,
            fromKey: key.fromKey,
            toKey: key.toKey,
          );
    });

// ------------------------------------------------------------------ teacher

/// A teacher's week (own timetable, or an admin looking at one teacher).
class TeacherWeek extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String teacherStaffId;
  final String mondayKey;

  const TeacherWeek({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.teacherStaffId,
    required this.mondayKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      teacherStaffId: teacherStaffId,
    );
    final bundles = ref.watch(teacherBundlesProvider(key));
    final monday = AttendanceDate.parse(mondayKey);
    final sunday = AttendanceDate.key(
      DateTime.utc(monday.year, monday.month, monday.day + 6),
    );
    final subs = ref.watch(
      teacherSubstitutionsProvider((
        schoolId: schoolId,
        branchId: branchId,
        teacherStaffId: teacherStaffId,
        fromKey: mondayKey,
        toKey: sunday,
      )),
    );
    return bundles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(teacherBundlesProvider(key)),
      ),
      data: (list) {
        // Periods this teacher covers belong to other teachers' timetables:
        // their cells are not in `list`, but the substitution carries the
        // slot's time, class and subject, so it is shown from there.
        final items = buildWeek(
          bundles: list,
          mondayKey: mondayKey,
          substitutions: subs.value ?? const [],
          onlyTeacherId: teacherStaffId,
          showClass: true,
          showTeacher: false,
        );
        final covers = subs.value ?? const <Substitution>[];
        for (final s in covers) {
          if (!s.isActive || s.substituteTeacherId != teacherStaffId) continue;
          if (s.dateKey.compareTo(mondayKey) < 0 ||
              s.dateKey.compareTo(sunday) > 0) {
            continue;
          }
          (items[s.weekday] ??= []).add(
            AgendaItem(
              time:
                  '${ttDate(s.dateKey)} · P${s.periodNumber} · ${s.timeLabel}',
              title: '${s.subjectName} · ${s.classLabel ?? s.classId}',
              badge: 'You are covering for ${s.originalTeacherName}',
              highlight: true,
            ),
          );
        }
        final days = _usedDays(items);
        if (days.isEmpty) {
          return const EmptyView(
            icon: Icons.event_busy_outlined,
            message: 'No periods scheduled this week.',
          );
        }
        return WeekAgenda(days: days, items: items);
      },
    );
  }
}

/// `/timetable/teachers` — an admin looks up one teacher's week.
class TeacherTimetablePage extends StatelessWidget {
  const TeacherTimetablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher timetable')),
      body: TimetableScope(builder: (context, tt) => _TeacherPick(tt: tt)),
    );
  }
}

class _TeacherPick extends ConsumerStatefulWidget {
  final TimetableContext tt;

  const _TeacherPick({required this.tt});

  @override
  ConsumerState<_TeacherPick> createState() => _TeacherPickState();
}

class _TeacherPickState extends ConsumerState<_TeacherPick> {
  String? _teacher;
  String _monday = mondayOf(DateTime.now());

  void _shift(int weeks) {
    final m = AttendanceDate.parse(_monday);
    setState(
      () => _monday = AttendanceDate.key(
        DateTime.utc(m.year, m.month, m.day + 7 * weeks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final teachers = ref.watch(activeTeachersProvider(tt.branchKey));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ScopeBar(
            complete: _teacher != null,
            summary: _teacher == null
                ? 'Choose a teacher'
                : '${(teachers.value ?? const []).where((t) => t.staffId == _teacher).firstOrNull?.name ?? 'Teacher'} · '
                      'Week of ${ttDate(_monday)}',
            controlsBuilder: (context, narrow) => Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: narrow ? double.infinity : 260,
                  child: DropdownButtonFormField<String>(
                    value: _teacher,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Teacher',
                      isDense: true,
                    ),
                    items: [
                      for (final t in teachers.value ?? const [])
                        DropdownMenuItem(value: t.staffId, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _teacher = v),
                  ),
                ),
                WeekNavigator(
                  label: 'Week of ${ttDate(_monday)}',
                  onShift: _shift,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _teacher == null
              ? const EmptyView(
                  icon: Icons.person_outline,
                  message: 'Choose a teacher.',
                )
              : TeacherWeek(
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                  academicYearId: tt.year.academicYearId,
                  teacherStaffId: _teacher!,
                  mondayKey: _monday,
                ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- my timetable

/// `/my-timetable` — a teacher's own week with covers, or a parent's view of
/// the linked child's class. Read-only for both.
class MyTimetablePage extends ConsumerWidget {
  const MyTimetablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: pageAppBar(
        context,
        title: const Text('My timetable'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/my-leave/notifications'),
          ),
        ],
      ),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final school = tenant?.school;
          if (tenant == null || school == null) {
            return const EmptyView(
              icon: Icons.schedule_outlined,
              message: 'No school found for your account.',
            );
          }
          return tenant.role == UserRole.parent
              ? _ParentTimetable(tenant: tenant, schoolId: school.schoolId)
              : _TeacherTimetable(tenant: tenant, schoolId: school.schoolId);
        },
      ),
    );
  }
}

AcademicYear? _activeYear(List<AcademicYear> years, String? preferred) {
  if (years.isEmpty) return null;
  return years.firstWhere(
    (y) => y.academicYearId == preferred,
    orElse: () => years.firstWhere(
      (y) => y.status == AcademicYearStatus.active,
      orElse: () => years.first,
    ),
  );
}

class _TeacherTimetable extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;

  const _TeacherTimetable({required this.tenant, required this.schoolId});

  @override
  ConsumerState<_TeacherTimetable> createState() => _TeacherTimetableState();
}

class _TeacherTimetableState extends ConsumerState<_TeacherTimetable> {
  String _monday = mondayOf(DateTime.now());

  void _shift(int weeks) {
    final m = AttendanceDate.parse(_monday);
    setState(
      () => _monday = AttendanceDate.key(
        DateTime.utc(m.year, m.month, m.day + 7 * weeks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final branchId = tenant.user.branchId ?? tenant.branch?.branchId;
    if (branchId == null) {
      return const EmptyView(
        icon: Icons.schedule_outlined,
        message: 'No branch found for your account.',
      );
    }
    final own = ref.watch(
      ownStaffProvider((
        schoolId: widget.schoolId,
        branchId: branchId,
        userId: tenant.user.userId,
      )),
    );
    final years = ref.watch(
      academicYearsProvider((schoolId: widget.schoolId, branchId: branchId)),
    );
    return own.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (staff) {
        if (staff == null) {
          return const EmptyView(
            icon: Icons.link_off,
            message:
                "Your account isn't linked to a staff record, so there is no "
                'timetable to show. Please contact the school office.',
          );
        }
        final year = _activeYear(years.value ?? const [], null);
        if (year == null) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message: 'The school has not set up an academic year yet.',
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    staff.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  WeekNavigator(
                    label: 'Week of ${ttDate(_monday)}',
                    onShift: _shift,
                  ),
                ],
              ),
            ),
            Expanded(
              child: TeacherWeek(
                schoolId: widget.schoolId,
                branchId: branchId,
                academicYearId: year.academicYearId,
                teacherStaffId: staff.staffId,
                mondayKey: _monday,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParentTimetable extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;

  const _ParentTimetable({required this.tenant, required this.schoolId});

  @override
  ConsumerState<_ParentTimetable> createState() => _ParentTimetableState();
}

class _ParentTimetableState extends ConsumerState<_ParentTimetable> {
  String? _childId;
  String _monday = mondayOf(DateTime.now());

  void _shift(int weeks) {
    final m = AttendanceDate.parse(_monday);
    setState(
      () => _monday = AttendanceDate.key(
        DateTime.utc(m.year, m.month, m.day + 7 * weeks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentId = widget.tenant.user.linkedParentId;
    if (parentId == null) {
      return const EmptyView(
        icon: Icons.link_off,
        message:
            "Your account isn't linked to a parent record yet. Please contact the school office.",
      );
    }
    final children = ref.watch(
      linkedChildrenProvider((schoolId: widget.schoolId, parentId: parentId)),
    );
    return children.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.child_care_outlined,
            message: 'No children are linked to your account yet.',
          );
        }
        final child = list.firstWhere(
          (c) => c.studentId == _childId,
          orElse: () => list.first,
        );
        if (child.currentClassId == null || child.currentSectionId == null) {
          return const EmptyView(
            icon: Icons.schedule_outlined,
            message: 'Your child has not been placed in a class yet.',
          );
        }
        final years =
            ref
                .watch(
                  academicYearsProvider((
                    schoolId: widget.schoolId,
                    branchId: child.branchId,
                  )),
                )
                .value ??
            const <AcademicYear>[];
        final year = _activeYear(years, child.currentAcademicYearId);
        if (year == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (list.length > 1)
                    for (final c in list)
                      ChoiceChip(
                        label: Text(c.displayName),
                        selected: c.studentId == child.studentId,
                        onSelected: (_) =>
                            setState(() => _childId = c.studentId),
                      )
                  else
                    Text(
                      child.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  WeekNavigator(
                    label: 'Week of ${ttDate(_monday)}',
                    onShift: _shift,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SectionWeek(
                schoolId: widget.schoolId,
                branchId: child.branchId,
                academicYearId: year.academicYearId,
                classId: child.currentClassId!,
                sectionId: child.currentSectionId!,
                mondayKey: _monday,
              ),
            ),
          ],
        );
      },
    );
  }
}
