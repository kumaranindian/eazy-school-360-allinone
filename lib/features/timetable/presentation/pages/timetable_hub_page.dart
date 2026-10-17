import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/weekday.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../domain/period_set.dart';
import '../../domain/timetable.dart';
import '../../domain/timetable_copy.dart';
import '../../domain/timetable_enums.dart';
import '../../domain/timetable_repositories.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../providers/timetable_providers.dart';
import '../widgets/timetable_format.dart';
import '../widgets/timetable_scope.dart';

/// `/timetable` — every version of every section's timetable for the year,
/// with what is in force, and the way into editing, bell schedules,
/// substitutions, the conflict report and history.
class TimetableHubPage extends StatelessWidget {
  const TimetableHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('Timetable')),
      body: TimetableScope(builder: (context, tt) => _Hub(tt: tt)),
    );
  }
}

class _Hub extends ConsumerStatefulWidget {
  final TimetableContext tt;

  const _Hub({required this.tt});

  @override
  ConsumerState<_Hub> createState() => _HubState();
}

class _HubState extends ConsumerState<_Hub> {
  String? _classId;
  TimetableStatus? _status;

  TimetableActor get _actor =>
      TimetableActor(userId: widget.tt.userId, name: widget.tt.userName);

  Future<void> _create({Timetable? copyFrom}) async {
    final tt = widget.tt;
    final created = await showAdaptiveAppDialog<String>(
      context: context,
      builder: (dialogContext) => NewTimetableForm(
        tt: tt,
        copyFrom: copyFrom,
        actor: _actor,
        onDone: (id) => Navigator.of(dialogContext).pop(id),
      ),
    );
    if (created != null && mounted) context.go('/timetable/editor/$created');
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final theme = Theme.of(context);
    final canManage = tt.tenant.can(Permission.manageTimetable);
    final all = ref.watch(timetablesProvider(tt.yearKey));
    final classes =
        ref.watch(classesProvider(tt.academicKey)).value ?? const [];

    Widget tile(IconData icon, String title, String description, String path) =>
        HubTile(
          icon: icon,
          title: title,
          description: description,
          onTap: () => context.go(path),
        );

    final List<FilterField> filters = [
      FilterField.dropdown<String>(
        label: 'Class',
        value: classes.any((c) => c.classId == _classId) ? _classId : null,
        options: [(null, 'All'), for (final c in classes) (c.classId, c.name)],
        onChanged: (v) => setState(() => _classId = v),
      ),
      FilterField.dropdown<TimetableStatus>(
        label: 'Status',
        value: _status,
        options: [
          (null, 'All'),
          for (final s in TimetableStatus.values) (s, s.displayName),
        ],
        onChanged: (v) => setState(() => _status = v),
      ),
    ];

    final body = ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        FilterBar(fieldsBuilder: () => filters),
        const SizedBox(height: AppSpacing.md),
        all.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: userMessageFor(e),
            onRetry: () => ref.invalidate(timetablesProvider(tt.yearKey)),
          ),
          data: (list) {
            final shown = [
              for (final t in list)
                if ((_classId == null || t.classId == _classId) &&
                    (_status == null || t.status == _status))
                  t,
            ];
            if (shown.isEmpty) {
              return EmptyView(
                icon: Icons.calendar_view_week_outlined,
                message: list.isEmpty
                    ? 'No timetables yet for this academic year.'
                    : 'No timetables match these filters.',
              );
            }
            return Column(
              children: [
                for (final t in shown)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      title: Text('${t.title} · v${t.version}'),
                      subtitle: Text(
                        '${t.name} · ${ttRange(t)} · ${t.entryCount} period${t.entryCount == 1 ? '' : 's'}',
                      ),
                      trailing: Wrap(
                        spacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(t.status.displayName),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: t.isPublished
                                ? theme.colorScheme.primaryContainer
                                : null,
                          ),
                          if (canManage && t.status != TimetableStatus.draft)
                            IconButton(
                              tooltip: 'New version from this',
                              icon: const Icon(Icons.copy_all_outlined),
                              onPressed: () => _create(copyFrom: t),
                            ),
                        ],
                      ),
                      onTap: () =>
                          context.go('/timetable/editor/${t.timetableId}'),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Timetable views',
          tiles: [
            tile(
              Icons.grid_view,
              'Class timetable',
              'The week for one class and section',
              '/timetable/view',
            ),
            tile(
              Icons.person_outline,
              'Teacher timetable',
              'The week for one teacher',
              '/timetable/teachers',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Plan and check',
          tiles: [
            tile(
              Icons.access_time,
              'Bell schedules',
              'Period times for each day',
              '/timetable/periods',
            ),
            tile(
              Icons.swap_horiz,
              'Substitutions',
              'Cover for absent teachers, by date',
              '/timetable/substitutions',
            ),
            tile(
              Icons.rule,
              'Conflict report',
              'Clashes between teachers, rooms and periods',
              '/timetable/conflicts',
            ),
            tile(
              Icons.history,
              'History',
              'Every version and who changed it',
              '/timetable/history',
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _create(),
              icon: const Icon(Icons.add),
              label: const Text('New timetable'),
            )
          : null,
      body: body,
    );
  }
}

/// Create a draft: a new empty timetable, or a copy of an existing version
/// (into the same section as a new version, or into another section with its
/// own teachers).
class NewTimetableForm extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final Timetable? copyFrom;
  final TimetableActor actor;
  final ValueChanged<String> onDone;

  const NewTimetableForm({
    super.key,
    required this.tt,
    required this.copyFrom,
    required this.actor,
    required this.onDone,
  });

  @override
  ConsumerState<NewTimetableForm> createState() => _NewTimetableFormState();
}

class _NewTimetableFormState extends ConsumerState<NewTimetableForm> {
  final _name = TextEditingController();
  String? _classId;
  String? _sectionId;
  DateTime? _from;
  DateTime? _to;
  final Map<String, String?> _sets = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.copyFrom;
    if (c != null) {
      _classId = c.classId;
      _sectionId = c.sectionId;
      _name.text = c.name;
      _sets.addAll(c.dayPeriodSets);
    } else {
      _name.text = 'Timetable';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _key(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool from) async {
    final y = widget.tt.year;
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? y.startDate.toUtc(),
      firstDate: y.startDate.toUtc(),
      lastDate: y.endDate.toUtc(),
    );
    if (picked != null) {
      setState(() => from ? _from = picked : _to = picked);
    }
  }

  Future<void> _submit(
    List<PeriodSet> allSets,
    List<SchoolClass> classes,
    List<Section> sections,
  ) async {
    final tt = widget.tt;
    final cls = classes.where((c) => c.classId == _classId).firstOrNull;
    final sec = sections.where((s) => s.sectionId == _sectionId).firstOrNull;
    if (cls == null || sec == null) {
      setState(() => _error = 'Choose the class and section.');
      return;
    }
    final template = Timetable(
      timetableId: '-',
      schoolId: tt.schoolId,
      branchId: tt.branchId,
      academicYearId: tt.year.academicYearId,
      classId: cls.classId,
      sectionId: sec.sectionId,
      className: cls.name,
      sectionName: sec.name,
      name: _name.text.trim(),
      version: 0,
      dayPeriodSets: {
        for (final e in _sets.entries)
          if (e.value != null) e.key: e.value!,
      },
      effectiveFromKey: _key(_from) ?? '',
      effectiveToKey: _key(_to),
      copiedFrom: widget.copyFrom?.timetableId,
    );
    final problem = template.validateMeta(
      yearStartKey: tt.yearStartKey,
      yearEndKey: tt.yearEndKey,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var entries = const <TimetableEntry>[];
      var skipped = const <String>[];
      final src = widget.copyFrom;
      if (src != null) {
        final repo = ref.read(timetableRepositoryProvider);
        final cells = await repo.fetchEntries(
          src.schoolId,
          src.branchId,
          src.timetableId,
        );
        if (src.classId == cls.classId && src.sectionId == sec.sectionId) {
          entries = cells;
        } else {
          final assignments = await readAlive(
            ref,
            yearAssignmentsProvider(tt.yearKey),
          );
          final teachers = await readAlive(
            ref,
            activeTeachersProvider(tt.branchKey),
          );
          final names = {for (final s in teachers) s.staffId: s.name};
          final map = <String, SectionTeacher>{
            for (final a in assignments)
              if (!a.isClassTeacher &&
                  a.subjectId != null &&
                  a.classId == cls.classId &&
                  a.sectionId == sec.sectionId &&
                  names.containsKey(a.teacherStaffId))
                a.subjectId!: SectionTeacher(
                  a.teacherStaffId,
                  names[a.teacherStaffId]!,
                ),
          };
          final res = TimetableCopier.toSection(
            entries: cells,
            target: template,
            teacherBySubject: map,
          );
          entries = res.entries;
          skipped = res.skipped;
        }
      }
      final created = await ref
          .read(timetableRepositoryProvider)
          .createDraft(
            template: template,
            entries: entries,
            actor: widget.actor,
          );
      ref.invalidate(timetablesProvider(tt.yearKey));
      if (!mounted) return;
      if (skipped.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${skipped.length} period(s) were not copied: no teacher is '
              'assigned for that subject in the new section.',
            ),
          ),
        );
      }
      widget.onDone(created.timetableId);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final classes =
        ref.watch(classesProvider(tt.academicKey)).value ??
        const <SchoolClass>[];
    final sections = _classId == null
        ? const <Section>[]
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
              const <Section>[];
    final sets =
        ref.watch(periodSetsProvider(tt.yearKey)).value ?? const <PeriodSet>[];
    final working = ref.watch(workingDaysProvider(tt.branchKey)).value;
    final days = <Weekday>[
      if (working != null)
        for (final d in Weekday.values)
          if (working.isWorkingDay[d] ?? false) d,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.copyFrom == null ? 'New timetable' : 'New version / copy',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          value: _classId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [
            for (final c in classes)
              DropdownMenuItem(value: c.classId, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() {
            _classId = v;
            _sectionId = null;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          value: _sectionId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Section'),
          items: [
            for (final s in sections)
              DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _sectionId = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.event),
              label: Text(
                _from == null
                    ? 'Effective from'
                    : 'From ${ttDate(_key(_from)!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.event_available),
              label: Text(
                _to == null
                    ? 'Until (optional)'
                    : 'Until ${ttDate(_key(_to)!)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Bell schedule per working day',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (sets.isEmpty)
          const Text('Create a bell schedule first (Bell schedules).')
        else
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: DropdownButtonFormField<String?>(
                value: sets.any((s) => s.periodSetId == _sets[d.wireValue])
                    ? _sets[d.wireValue]
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: d.displayName,
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not used')),
                  for (final s in sets)
                    DropdownMenuItem(value: s.periodSetId, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _sets[d.wireValue] = v),
              ),
            ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: AppSpacing.sm,
          overflowSpacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _submit(sets, classes, sections),
              child: const Text('Create draft'),
            ),
          ],
        ),
      ],
    );
  }
}
