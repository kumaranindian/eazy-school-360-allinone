import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/weekday.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../domain/period_set.dart';
import '../../domain/timetable.dart';
import '../../domain/timetable_copy.dart';
import '../../domain/timetable_repositories.dart';
import '../../domain/timetable_validation.dart';
import '../providers/timetable_providers.dart';
import '../widgets/issue_list.dart';
import '../widgets/timetable_format.dart';
import '../widgets/timetable_scope.dart';
import '../widgets/week_agenda.dart';

/// `/timetable/editor/:timetableId` — edit a DRAFT cell by cell, validate,
/// preview, publish. A published or archived version opens read-only: a
/// change is a new version, never an edit.
class TimetableEditorPage extends StatelessWidget {
  final String timetableId;

  const TimetableEditorPage({super.key, required this.timetableId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        leading: BackButton(onPressed: () => context.go('/timetable')),
      ),
      body: TimetableScope(
        showYearSelector: false,
        builder: (context, tt) => _Editor(tt: tt, timetableId: timetableId),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final String timetableId;

  const _Editor({required this.tt, required this.timetableId});

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  Map<String, TimetableEntry>? _cells;
  Map<String, TimetableEntry> _saved = {};
  Timetable? _loaded;
  List<TimetableIssue>? _issues;
  bool _busy = false;
  bool _preview = false;
  String? _error;

  TimetableIdKey get _key => (
    schoolId: widget.tt.schoolId,
    branchId: widget.tt.branchId,
    timetableId: widget.timetableId,
  );

  TimetableActor get _actor =>
      TimetableActor(userId: widget.tt.userId, name: widget.tt.userName);

  bool get _dirty {
    final cells = _cells;
    if (cells == null) return false;
    if (cells.length != _saved.length) return true;
    for (final e in cells.entries) {
      final s = _saved[e.key];
      if (s == null ||
          s.subjectId != e.value.subjectId ||
          s.teacherStaffId != e.value.teacherStaffId ||
          (s.room ?? '') != (e.value.room ?? '')) {
        return true;
      }
    }
    return false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<TimetableEntry> get _entryList => _cells!.values.toList();

  Future<void> _save(Timetable t) async {
    final cells = _cells!;
    final upserts = <TimetableEntry>[
      for (final e in cells.values)
        if (_saved[e.entryId] == null ||
            _saved[e.entryId]!.subjectId != e.subjectId ||
            _saved[e.entryId]!.teacherStaffId != e.teacherStaffId ||
            (_saved[e.entryId]!.room ?? '') != (e.room ?? ''))
          e,
    ];
    final removals = <TimetableEntry>[
      for (final e in _saved.values)
        if (!cells.containsKey(e.entryId)) e,
    ];
    await ref
        .read(timetableRepositoryProvider)
        .saveDraft(
          timetable: t,
          upserts: upserts,
          removals: removals,
          teacherIds: {for (final e in cells.values) e.teacherStaffId}.toList(),
          entryCount: cells.length,
          actor: _actor,
        );
    _saved = {for (final e in cells.entries) e.key: e.value};
    ref.invalidate(timetableEntriesProvider(_key));
    ref.invalidate(timetablesProvider(widget.tt.yearKey));
  }

  Future<List<TimetableIssue>> _validate(
    Timetable t,
    Map<String, PeriodSet> sets,
  ) async {
    final tt = widget.tt;
    final published = await readAlive(
      ref,
      publishedBundlesProvider(tt.yearKey),
    );
    final assignments = await readAlive(
      ref,
      yearAssignmentsProvider(tt.yearKey),
    );
    final teachers = await readAlive(ref, activeTeachersProvider(tt.branchKey));
    final workingDays = await readAlive(ref, workingDaysProvider(tt.branchKey));
    final leave = await readAlive(
      ref,
      staffLeaveRangeProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        fromKey: t.effectiveFromKey,
        toKey: t.effectiveToKey ?? tt.yearEndKey,
      )),
    );
    return TimetableValidator.validate(
      candidate: TimetableBundle(t, _entryList),
      periodSets: sets,
      workingWeekdays: {
        for (final e in workingDays.isWorkingDay.entries)
          if (e.value) e.key.wireValue,
      },
      otherPublished: published,
      sectionAssignments: [
        for (final a in assignments)
          if (a.classId == t.classId && a.sectionId == t.sectionId) a,
      ],
      activeTeacherIds: {for (final s in teachers) s.staffId},
      staffLeave: leave,
    );
  }

  Future<void> _publish(Timetable t, Map<String, PeriodSet> sets) async {
    // Prepare (saves, snapshots the world and the lock sequence, validates),
    // then ask — without a busy indicator while the person decides — then
    // commit. The sequence is taken *before* validating, so the publish is
    // refused if anything was published in between.
    ({
      Timetable timetable,
      int sequence,
      SupersessionPlan plan,
      List<TimetableIssue> issues,
      List<Recipient> recipients,
    })?
    prepared;
    await _guard(() async {
      final repo = ref.read(timetableRepositoryProvider);
      if (_dirty) await _save(t);
      final fresh = (await ref.refresh(timetableProvider(_key).future)) ?? t;
      final sequence = await repo.publishSequence(
        widget.tt.schoolId,
        widget.tt.branchId,
      );
      ref.invalidate(publishedBundlesProvider(widget.tt.yearKey));
      final issues = await _validate(fresh, sets);
      if (!mounted) return;
      setState(() => _issues = issues);
      final refusal = TimetablePublication.checkPublish(fresh, issues);
      if (refusal != null) {
        _snack(refusal);
        return;
      }
      final published = await readAlive(
        ref,
        publishedBundlesProvider(widget.tt.yearKey),
      );
      final plan = TimetablePublication.planSupersession(
        fresh,
        published.map((b) => b.timetable),
      );
      final teachers = await readAlive(
        ref,
        activeTeachersProvider(widget.tt.branchKey),
      );
      final byId = {for (final s in teachers) s.staffId: s};
      final recipients = <Recipient>[
        for (final id in {for (final e in _entryList) e.teacherStaffId})
          if (byId[id]?.userId != null && byId[id]!.userId != widget.tt.userId)
            Recipient(
              userId: byId[id]!.userId!,
              staffId: id,
              name: byId[id]!.name,
            ),
      ];
      prepared = (
        timetable: fresh,
        sequence: sequence,
        plan: plan,
        issues: issues,
        recipients: recipients,
      );
    });
    final p = prepared;
    if (p == null || !mounted) return;
    final confirmed = await _confirmPublish(
      p.timetable,
      p.plan,
      p.issues,
      p.recipients,
    );
    if (confirmed != true) return;
    await _guard(() async {
      await ref
          .read(timetableRepositoryProvider)
          .publish(
            timetable: p.timetable,
            entries: _entryList,
            supersession: p.plan,
            expectedSequence: p.sequence,
            recipients: p.recipients,
            actor: _actor,
          );
      ref.invalidate(timetablesProvider(widget.tt.yearKey));
      ref.invalidate(publishedBundlesProvider(widget.tt.yearKey));
      ref.invalidate(timetableEntriesProvider(_key));
      _snack('Timetable published.');
    });
  }

  Future<bool?> _confirmPublish(
    Timetable t,
    SupersessionPlan plan,
    List<TimetableIssue> issues,
    List<Recipient> recipients,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish this timetable?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t.title} · v${t.version} · ${ttRange(t)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final a in plan.archive)
                Text(
                  '• Replaces v${a.version} (${ttRange(a)}); it is archived.',
                ),
              for (final x in plan.truncate)
                Text(
                  '• v${x.timetable.version} ends on ${ttDate(x.newEndKey)}.',
                ),
              if (plan.isEmpty)
                const Text('• No other version of this section is in force.'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${recipients.length} teacher${recipients.length == 1 ? '' : 's'} '
                'will be notified in the app.',
              ),
              if (issues.any((i) => !i.isError)) ...[
                const SizedBox(height: AppSpacing.md),
                IssueList(issues: issues),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Published versions are never edited; to change it later you '
                'create a new version.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCell(
    Timetable t,
    PeriodSlot slot,
    Weekday day,
    Map<String, SubjectChoice> choices,
  ) async {
    final id = TimetableEntry.idFor(t.timetableId, day, slot.slotId);
    final existing = _cells![id];
    final result = await showAdaptiveAppDialog<_CellEdit>(
      context: context,
      builder: (dialogContext) => _CellDialog(
        title: '${day.displayName} · period ${slot.number} · ${slot.timeLabel}',
        choices: choices,
        initialSubjectId: existing?.subjectId,
        initialRoom: existing?.room,
        canClear: existing != null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _issues = null;
      if (result.clear) {
        _cells!.remove(id);
        return;
      }
      final c = choices[result.subjectId]!;
      _cells![id] = TimetableEntry(
        entryId: id,
        timetableId: t.timetableId,
        schoolId: t.schoolId,
        branchId: t.branchId,
        academicYearId: t.academicYearId,
        classId: t.classId,
        sectionId: t.sectionId,
        weekday: day,
        slotId: slot.slotId,
        periodNumber: slot.number!,
        startMin: slot.startMin,
        endMin: slot.endMin,
        subjectId: c.subjectId,
        subjectName: c.subjectName,
        teacherStaffId: c.teacherStaffId,
        teacherName: c.teacherName,
        room: (result.room ?? '').trim().isEmpty ? null : result.room!.trim(),
      );
    });
  }

  Future<void> _copyDay(
    Timetable t,
    Map<String, PeriodSet> sets,
    Weekday day,
  ) async {
    final days = orderedDays(
      t.dayPeriodSets.keys,
    ).where((d) => d != day).toList();
    final picked = await showDialog<List<Weekday>>(
      context: context,
      builder: (context) {
        final chosen = <Weekday>{};
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Copy ${day.displayName} to…'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in days)
                  CheckboxListTile(
                    value: chosen.contains(d),
                    title: Text(d.displayName),
                    onChanged: (v) => setLocal(
                      () => v == true ? chosen.add(d) : chosen.remove(d),
                    ),
                  ),
                const Text(
                  'Existing periods on those days are replaced.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, chosen.toList()),
                child: const Text('Copy'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final result = TimetableCopier.copyDay(
      timetable: t,
      entries: _entryList,
      day: day,
      targets: picked,
      periodSets: sets,
    );
    setState(() {
      _issues = null;
      _cells!.removeWhere((_, e) => picked.contains(e.weekday));
      for (final e in result.entries) {
        _cells![e.entryId] = e;
      }
    });
    _snack(
      result.skipped.isEmpty
          ? 'Copied ${day.displayName}.'
          : 'Copied, but ${result.skipped.length} period(s) had no match.',
    );
  }

  Future<void> _discard(Timetable t) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t.isDraft ? 'Discard this draft?' : 'Withdraw this timetable?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.isDraft
                  ? 'The draft is archived; nothing in force changes.'
                  : 'It stops being in force. Substitutions already made '
                        'against it are flagged for review.',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(t.isDraft ? 'Discard' : 'Withdraw'),
          ),
        ],
      ),
    );
    // not disposed here: the dialog is still animating out and the field
    // would be used after dispose; a controller holds no native resource.
    if (reason == null || !mounted) return;
    await _guard(() async {
      await ref
          .read(timetableRepositoryProvider)
          .archive(
            timetable: t,
            entries: _entryList,
            reason: reason,
            actor: _actor,
          );
      ref.invalidate(timetablesProvider(widget.tt.yearKey));
      ref.invalidate(publishedBundlesProvider(widget.tt.yearKey));
      _snack('Timetable archived.');
      if (mounted) context.go('/timetable');
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final ttAsync = ref.watch(timetableProvider(_key));
    final entriesAsync = ref.watch(timetableEntriesProvider(_key));
    final setsAsync = ref.watch(periodSetsProvider(tt.yearKey));
    if (ttAsync.isLoading || entriesAsync.isLoading || setsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = ttAsync.error ?? entriesAsync.error ?? setsAsync.error;
    if (err != null) {
      return ErrorView(
        message: userMessageFor(err),
        onRetry: () {
          ref.invalidate(timetableEntriesProvider(_key));
          ref.invalidate(periodSetsProvider(tt.yearKey));
        },
      );
    }
    final t = ttAsync.value;
    if (t == null) {
      return const EmptyView(
        icon: Icons.search_off,
        message: 'This timetable could not be found.',
      );
    }
    if (_cells == null || _loaded?.revision != t.revision) {
      final fromDb = {
        for (final e in entriesAsync.value ?? const <TimetableEntry>[])
          e.entryId: e,
      };
      // Keep unsaved edits unless the document moved under us.
      if (_cells == null || !_dirty) {
        _cells = Map.of(fromDb);
        _saved = Map.of(fromDb);
      }
      _loaded = t;
    }
    final sets = {
      for (final s in setsAsync.value ?? const <PeriodSet>[]) s.periodSetId: s,
    };
    final editable =
        t.isDraft && tt.tenant.can(Permission.manageTimetable) && !_preview;
    final days = orderedDays(t.dayPeriodSets.keys);

    // Subject choices: subjects with an ACTIVE assignment in this section.
    final assignments =
        ref.watch(yearAssignmentsProvider(tt.yearKey)).value ?? const [];
    final teachers =
        ref.watch(activeTeachersProvider(tt.branchKey)).value ?? const [];
    final names = {for (final s in teachers) s.staffId: s.name};
    final subjects =
        ref.watch(yearSubjectsProvider(tt.yearKey)).value ?? const {};
    final choices = <String, SubjectChoice>{
      for (final a in assignments)
        if (!a.isClassTeacher &&
            a.subjectId != null &&
            a.classId == t.classId &&
            a.sectionId == t.sectionId &&
            names.containsKey(a.teacherStaffId))
          a.subjectId!: SubjectChoice(
            subjectId: a.subjectId!,
            subjectName: subjects[a.subjectId]?.name ?? a.subjectId!,
            teacherStaffId: a.teacherStaffId,
            teacherName: names[a.teacherStaffId]!,
          ),
    };

    final items = <Weekday, List<AgendaItem>>{};
    for (final d in days) {
      final set = sets[t.dayPeriodSets[d.wireValue]];
      if (set == null) {
        items[d] = const [
          AgendaItem(
            time: '',
            title: 'The period schedule for this day no longer exists.',
            isEmpty: true,
          ),
        ];
        continue;
      }
      final slots = [...set.slots]
        ..sort((a, b) => a.startMin.compareTo(b.startMin));
      items[d] = [
        for (final s in slots)
          if (!s.isTeaching)
            AgendaItem(time: s.timeLabel, title: s.label, isBreak: true)
          else
            () {
              final e =
                  _cells![TimetableEntry.idFor(t.timetableId, d, s.slotId)];
              final conflicted =
                  _issues?.any(
                    (i) => i.isError && i.weekday == d && i.slotId == s.slotId,
                  ) ??
                  false;
              return AgendaItem(
                time: 'Period ${s.number} · ${s.timeLabel}',
                title: e == null
                    ? (editable ? 'Tap to assign' : 'Free')
                    : e.subjectName,
                subtitle: e == null
                    ? null
                    : '${e.teacherName}${e.room == null ? '' : ' · ${e.room}'}',
                isEmpty: e == null,
                highlight: conflicted,
                onTap: editable ? () => _editCell(t, s, d, choices) : null,
              );
            }(),
      ];
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${t.title} · v${t.version}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Chip(
                    label: Text(t.status.displayName),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(ttRange(t)),
                ],
              ),
              if (!t.isDraft)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'This version is read-only. Create a new version to change it.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (t.isDraft && tt.tenant.can(Permission.manageTimetable))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || !_dirty
                            ? null
                            : () => _guard(() async {
                                await _save(t);
                                _snack('Draft saved.');
                              }),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save draft'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _guard(() async {
                                final issues = await _validate(t, sets);
                                if (mounted) setState(() => _issues = issues);
                              }),
                        icon: const Icon(Icons.rule),
                        label: const Text('Validate'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _preview = !_preview),
                        icon: Icon(
                          _preview
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                        ),
                        label: Text(_preview ? 'Back to editing' : 'Preview'),
                      ),
                      if (tt.tenant.can(Permission.publishTimetable))
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _publish(t, sets),
                          icon: const Icon(Icons.publish),
                          label: const Text('Publish'),
                        ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _discard(t),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Discard draft'),
                      ),
                    ],
                  ),
                ),
              if (t.isPublished && tt.tenant.can(Permission.publishTimetable))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _discard(t),
                    icon: const Icon(Icons.unpublished_outlined),
                    label: const Text('Withdraw'),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_issues != null)
                Card(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: IssueList(issues: _issues!),
                  ),
                ),
            ],
          ),
        ),
        if (editable && days.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ActionChip(
                      label: Text('Copy ${d.displayName.substring(0, 3)} to…'),
                      onPressed: () => _copyDay(t, sets, d),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: WeekAgenda(days: days, items: items),
        ),
      ],
    );
  }
}

/// A subject the section can be given, with its (only) assigned teacher.
class SubjectChoice {
  final String subjectId;
  final String subjectName;
  final String teacherStaffId;
  final String teacherName;

  const SubjectChoice({
    required this.subjectId,
    required this.subjectName,
    required this.teacherStaffId,
    required this.teacherName,
  });
}

class _CellEdit {
  final String? subjectId;
  final String? room;
  final bool clear;

  const _CellEdit({this.subjectId, this.room, this.clear = false});
}

class _CellDialog extends StatefulWidget {
  final String title;
  final Map<String, SubjectChoice> choices;
  final String? initialSubjectId;
  final String? initialRoom;
  final bool canClear;

  const _CellDialog({
    required this.title,
    required this.choices,
    required this.initialSubjectId,
    required this.initialRoom,
    required this.canClear,
  });

  @override
  State<_CellDialog> createState() => _CellDialogState();
}

class _CellDialogState extends State<_CellDialog> {
  late String? _subject = widget.choices.containsKey(widget.initialSubjectId)
      ? widget.initialSubjectId
      : null;
  late final TextEditingController _room = TextEditingController(
    text: widget.initialRoom ?? '',
  );

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.choices.values.toList()
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        if (choices.isEmpty)
          const Text(
            'No subject of this section has an assigned teacher yet. '
            'Assign teachers in Staff first.',
          )
        else
          DropdownButtonFormField<String>(
            value: _subject,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Subject and teacher'),
            items: [
              for (final c in choices)
                DropdownMenuItem(
                  value: c.subjectId,
                  child: Text('${c.subjectName} — ${c.teacherName}'),
                ),
            ],
            onChanged: (v) => setState(() => _subject = v),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _room,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Room (optional)',
            helperText:
                'Free text; the same room cannot be used twice at once.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: AppSpacing.sm,
          overflowSpacing: AppSpacing.sm,
          children: [
            if (widget.canClear)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _CellEdit(clear: true)),
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _subject == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      _CellEdit(subjectId: _subject, room: _room.text),
                    ),
              child: const Text('Set period'),
            ),
          ],
        ),
      ],
    );
  }
}
