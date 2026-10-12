import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../leave/domain/leave_application.dart';
import '../../../leave/domain/leave_enums.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import '../../domain/substitution.dart';
import '../../domain/timetable_enums.dart';
import '../../domain/timetable_repositories.dart';
import '../providers/timetable_providers.dart';
import '../widgets/timetable_format.dart';
import '../widgets/timetable_scope.dart';

String _today() => AttendanceDate.key(DateTime.now());

String _plusDays(String key, int days) {
  final d = AttendanceDate.parse(key);
  return AttendanceDate.key(DateTime.utc(d.year, d.month, d.day + days));
}

/// The people to tell about a change to [s]: the substitute and the original
/// teacher (never the leave reason — notices carry the class, period, date).
List<Recipient> _recipients(
  Substitution s,
  List<StaffLite> teachers, {
  String? alsoSubstitute,
  required String actorUserId,
}) {
  final ids = {s.substituteTeacherId, s.originalTeacherId, ?alsoSubstitute};
  return [
    for (final t in teachers)
      if (ids.contains(t.staffId) &&
          t.userId != null &&
          t.userId != actorUserId)
        Recipient(userId: t.userId!, staffId: t.staffId, name: t.name),
  ];
}

// ----------------------------------------------------------------- list

/// `/timetable/substitutions` — covers for a date range, each re-validated
/// against today's leave and timetable: a cover whose leave was cancelled, or
/// whose substitute has since gone on leave, is flagged for review (never
/// changed automatically).
class SubstitutionsPage extends StatelessWidget {
  const SubstitutionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Substitutions')),
      body: TimetableScope(builder: (context, tt) => _Subs(tt: tt)),
    );
  }
}

class _Subs extends ConsumerStatefulWidget {
  final TimetableContext tt;

  const _Subs({required this.tt});

  @override
  ConsumerState<_Subs> createState() => _SubsState();
}

class _SubsState extends ConsumerState<_Subs> {
  late String _from = _today();
  late String _to = _plusDays(_today(), 14);
  bool _busy = false;

  Future<void> _pick(bool from) async {
    final y = widget.tt.year;
    final picked = await showDatePicker(
      context: context,
      initialDate: AttendanceDate.parse(from ? _from : _to),
      firstDate: y.startDate.toUtc(),
      lastDate: y.endDate.toUtc(),
    );
    if (picked == null) return;
    setState(() {
      final k = AttendanceDate.key(picked);
      if (from) {
        _from = k;
        if (_to.compareTo(_from) < 0) _to = k;
      } else {
        _to = k;
        if (_from.compareTo(_to) > 0) _from = k;
      }
    });
  }

  TimetableActor get _actor =>
      TimetableActor(userId: widget.tt.userId, name: widget.tt.userName);

  Future<void> _cancel(Substitution s) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this cover?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.classLabel} · ${s.subjectName} · period ${s.periodNumber} '
              'on ${ttDate(s.dateKey)}. The regular teacher is back in the '
              'timetable for that period.',
            ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 3) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Cancel cover'),
          ),
        ],
      ),
    );
    // not disposed here: the dialog is still animating out and the field
    // would be used after dispose; a controller holds no native resource.
    if (reason == null || !mounted) return;
    await _run(() async {
      final repo = ref.read(substitutionRepositoryProvider);
      final teachers = await readAlive(
        ref,
        activeTeachersProvider(widget.tt.branchKey),
      );
      final seq = await repo.daySequence(s.schoolId, s.branchId, s.dateKey);
      await repo.cancel(
        current: s,
        reason: reason,
        expectedSequence: seq,
        recipients: _recipients(s, teachers, actorUserId: widget.tt.userId),
        actor: _actor,
      );
    }, 'Cover cancelled.');
  }

  Future<void> _change(Substitution s) async {
    final tt = widget.tt;
    final teachers = await readAlive(ref, activeTeachersProvider(tt.branchKey));
    final assignments = await readAlive(
      ref,
      yearAssignmentsProvider(tt.yearKey),
    );
    final published = await readAlive(
      ref,
      publishedBundlesProvider(tt.yearKey),
    );
    final onDate = await readAlive(
      ref,
      substitutionsRangeProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        fromKey: s.dateKey,
        toKey: s.dateKey,
      )),
    );
    final leave = await readAlive(
      ref,
      staffLeaveRangeProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        fromKey: s.dateKey,
        toKey: s.dateKey,
      )),
    );
    final bundle = published
        .where((b) => b.timetable.timetableId == s.timetableId)
        .firstOrNull;
    final entry = bundle?.entries
        .where((e) => e.entryId == s.entryId)
        .firstOrNull;
    if (bundle == null || entry == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The timetable for this cover is no longer in force; cancel it '
            'and arrange a new one.',
          ),
        ),
      );
      return;
    }
    final period = AffectedPeriod(
      dateKey: s.dateKey,
      timetable: bundle.timetable,
      entry: entry,
      existing: s,
    );
    final candidates = SubstitutionPlanner.candidates(
      period: period,
      activeTeachers: teachers,
      yearAssignments: assignments,
      published: published,
      substitutionsOnDate: onDate,
      staffLeave: leave,
      ignoreSubstitutionId: s.substitutionId,
    );
    if (!mounted) return;
    final chosen = await showDialog<SubstituteCandidate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose another substitute'),
        children: [
          for (final c in candidates)
            if (c.staff.staffId != s.substituteTeacherId)
              SimpleDialogOption(
                onPressed: c.eligible ? () => Navigator.pop(context, c) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.staff.name,
                      style: TextStyle(
                        color: c.eligible
                            ? null
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (!c.eligible)
                      Text(
                        c.reasons.join(' '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    await _run(() async {
      final repo = ref.read(substitutionRepositoryProvider);
      final seq = await repo.daySequence(s.schoolId, s.branchId, s.dateKey);
      await repo.change(
        current: s,
        substituteTeacherId: chosen.staff.staffId,
        substituteTeacherName: chosen.staff.name,
        reason: s.reason,
        expectedSequence: seq,
        recipients: _recipients(
          s,
          teachers,
          alsoSubstitute: chosen.staff.staffId,
          actorUserId: tt.userId,
        ),
        actor: _actor,
      );
    }, 'Substitute changed.');
  }

  Future<void> _showHistory(Substitution s) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cover history · ${ttDate(s.dateKey)} P${s.periodNumber}'),
        content: SizedBox(
          width: 420,
          child: Consumer(
            builder: (context, ref, _) {
              final h = ref.watch(
                substitutionHistoryProvider((
                  schoolId: s.schoolId,
                  branchId: s.branchId,
                  substitutionId: s.substitutionId,
                )),
              );
              return h.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(userMessageFor(e)),
                data: (list) => list.isEmpty
                    ? const Text('No history yet.')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${e.event.wireValue.toLowerCase()} · '
                                '${e.substituteTeacherName} · ${e.actorName}'
                                '${(e.note ?? '').isEmpty ? '' : '\n${e.note}'}',
                              ),
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(substitutionsRangeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final canManage = tt.tenant.can(Permission.manageSubstitutions);
    final key = (
      schoolId: tt.schoolId,
      branchId: tt.branchId,
      fromKey: _from,
      toKey: _to,
    );
    final subs = ref.watch(substitutionsRangeProvider(key));
    final leave =
        ref.watch(staffLeaveRangeProvider(key)).value ??
        const <LeaveCalendarEntry>[];
    final published =
        ref.watch(publishedBundlesProvider(tt.yearKey)).value ?? const [];
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.event),
                label: Text('From ${ttDate(_from)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.event_available),
                label: Text('To ${ttDate(_to)}'),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => context.go('/timetable/substitutions/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Arrange cover'),
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: subs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(substitutionsRangeProvider(key)),
            ),
            data: (list) {
              final sorted = [...list]
                ..sort((a, b) {
                  final c = a.dateKey.compareTo(b.dateKey);
                  return c != 0 ? c : a.startMin.compareTo(b.startMin);
                });
              if (sorted.isEmpty) {
                return const EmptyView(
                  icon: Icons.swap_horiz,
                  message: 'No substitutions in this period.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final s in sorted)
                    Builder(
                      builder: (context) {
                        final warnings = SubstitutionHealth.check(
                          substitution: s,
                          staffLeave: leave,
                          published: published.map((b) => b.timetable),
                          bundles: published,
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${ttDate(s.dateKey)} · P${s.periodNumber} '
                                        '${s.timeLabel} · ${s.classLabel ?? s.classId}',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(s.status.displayName),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                Text(
                                  '${s.subjectName}: ${s.originalTeacherName} → '
                                  '${s.substituteTeacherName}',
                                ),
                                Text(
                                  '${s.reasonKind.displayName}'
                                  '${s.reason.isEmpty ? '' : ' · ${s.reason}'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (s.status == SubstitutionStatus.cancelled &&
                                    (s.cancelReason ?? '').isNotEmpty)
                                  Text(
                                    'Cancelled: ${s.cancelReason}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                for (final w in warnings)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_outlined,
                                          size: 18,
                                          color: theme.colorScheme.tertiary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(w.message)),
                                      ],
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _showHistory(s),
                                    icon: const Icon(Icons.history, size: 18),
                                    label: const Text('History'),
                                  ),
                                ),
                                if (canManage && s.isActive)
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _change(s),
                                        child: const Text('Change substitute'),
                                      ),
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _cancel(s),
                                        child: const Text('Cancel cover'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ arrange cover

/// `/timetable/substitutions/new` — find a teacher's affected periods in a
/// date range, see who can cover each (with the reason when someone cannot),
/// preview, and confirm. Suggestions are only suggestions: nothing is
/// assigned until an administrator chooses and confirms.
class NewSubstitutionPage extends StatelessWidget {
  const NewSubstitutionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrange cover'),
        leading: BackButton(
          onPressed: () => context.go('/timetable/substitutions'),
        ),
      ),
      body: TimetableScope(builder: (context, tt) => _New(tt: tt)),
    );
  }
}

class _New extends ConsumerStatefulWidget {
  final TimetableContext tt;

  const _New({required this.tt});

  @override
  ConsumerState<_New> createState() => _NewState();
}

class _NewState extends ConsumerState<_New> {
  String? _teacher;
  String _from = _today();
  String _to = _today();
  List<AffectedPeriod>? _affected;
  final Map<String, List<SubstituteCandidate>> _candidates = {};
  final Map<String, String?> _chosen = {};
  final Map<String, String?> _leaveFor = {};
  SubstitutionReasonKind _kind = SubstitutionReasonKind.leave;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  TimetableActor get _actor =>
      TimetableActor(userId: widget.tt.userId, name: widget.tt.userName);

  Future<void> _pick(bool from) async {
    final y = widget.tt.year;
    final picked = await showDatePicker(
      context: context,
      initialDate: AttendanceDate.parse(from ? _from : _to),
      firstDate: y.startDate.toUtc(),
      lastDate: y.endDate.toUtc(),
    );
    if (picked == null) return;
    setState(() {
      final k = AttendanceDate.key(picked);
      if (from) {
        _from = k;
        if (_to.compareTo(_from) < 0) _to = k;
      } else {
        _to = k;
        if (_from.compareTo(_to) > 0) _from = k;
      }
      _affected = null;
    });
  }

  Future<void> _find() async {
    final tt = widget.tt;
    if (_teacher == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final published = await readAlive(
        ref,
        publishedBundlesProvider(tt.yearKey),
      );
      final working = await readAlive(ref, workingDaysProvider(tt.branchKey));
      final holidays = await readAlive(ref, holidaysProvider(tt.academicKey));
      final subs = await readAlive(
        ref,
        substitutionsRangeProvider((
          schoolId: tt.schoolId,
          branchId: tt.branchId,
          fromKey: _from,
          toKey: _to,
        )),
      );
      final leave = await readAlive(
        ref,
        staffLeaveRangeProvider((
          schoolId: tt.schoolId,
          branchId: tt.branchId,
          fromKey: _from,
          toKey: _to,
        )),
      );
      final teachers = await readAlive(
        ref,
        activeTeachersProvider(tt.branchKey),
      );
      final assignments = await readAlive(
        ref,
        yearAssignmentsProvider(tt.yearKey),
      );
      final affected = SubstitutionPlanner.affected(
        teacherId: _teacher!,
        fromKey: _from,
        toKey: _to,
        published: published,
        workingDays: working,
        calendarEntries: holidays,
        substitutions: subs,
      );
      _candidates.clear();
      _chosen.clear();
      _leaveFor.clear();
      for (final p in affected) {
        final onDate = [
          for (final s in subs)
            if (s.dateKey == p.dateKey) s,
        ];
        _candidates[p.substitutionId] = SubstitutionPlanner.candidates(
          period: p,
          activeTeachers: teachers,
          yearAssignments: assignments,
          published: published,
          substitutionsOnDate: onDate,
          staffLeave: leave,
        );
        // Link to the leave the cover is for, by reference only.
        final l = leave
            .where(
              (x) =>
                  x.subjectId == _teacher &&
                  x.countedDateKeys.contains(p.dateKey),
            )
            .firstOrNull;
        _leaveFor[p.substitutionId] = l?.applicationId;
      }
      if (!mounted) return;
      setState(() {
        _affected = affected;
        _kind = _leaveFor.values.any((v) => v != null)
            ? SubstitutionReasonKind.leave
            : SubstitutionReasonKind.absence;
      });
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final tt = widget.tt;
    final affected = _affected!;
    final picks = <(AffectedPeriod, SubstituteCandidate)>[];
    for (final p in affected) {
      final id = _chosen[p.substitutionId];
      if (id == null || p.isCovered) continue;
      final c = _candidates[p.substitutionId]!
          .where((x) => x.staff.staffId == id)
          .first;
      picks.add((p, c));
    }
    if (picks.isEmpty) {
      setState(() => _error = 'Choose a substitute for at least one period.');
      return;
    }
    if (_reason.text.trim().length < 3 &&
        _kind == SubstitutionReasonKind.other) {
      setState(() => _error = 'Give a reason.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm these covers?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (p, c) in picks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${ttDate(p.dateKey)} · P${p.entry.periodNumber} '
                    '${p.entry.timeLabel} · ${p.timetable.title} '
                    '${p.entry.subjectName}\n   ${p.entry.teacherName} → ${c.staff.name}',
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'The regular timetable is not changed; the cover applies to '
                'these dates only. Both teachers are notified in the app.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm ${picks.length}'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(substitutionRepositoryProvider);
    var done = 0;
    try {
      final teachers = await readAlive(
        ref,
        activeTeachersProvider(tt.branchKey),
      );
      for (final (p, c) in picks) {
        // Re-check eligibility against the date as it is NOW, then commit
        // under that date's sequence: a cover made by someone else in the
        // meantime is refused rather than double-booked.
        final seq = await repo.daySequence(tt.schoolId, tt.branchId, p.dateKey);
        final published = await ref.refresh(
          publishedBundlesProvider(tt.yearKey).future,
        );
        final subsNow = await repo.fetchRange(
          schoolId: tt.schoolId,
          branchId: tt.branchId,
          fromKey: p.dateKey,
          toKey: p.dateKey,
        );
        final leave = await ref
            .read(leaveCalendarRepositoryProvider)
            .fetch(
              schoolId: tt.schoolId,
              branchId: tt.branchId,
              kind: LeaveKind.staff,
              fromKey: p.dateKey,
              toKey: p.dateKey,
            );
        final assignments = await readAlive(
          ref,
          yearAssignmentsProvider(tt.yearKey),
        );
        final fresh = SubstitutionPlanner.candidates(
          period: p,
          activeTeachers: teachers,
          yearAssignments: assignments,
          published: published,
          substitutionsOnDate: subsNow,
          staffLeave: leave,
        ).where((x) => x.staff.staffId == c.staff.staffId).first;
        if (!fresh.eligible) {
          throw StateError(
            '${c.staff.name} can no longer cover ${ttDate(p.dateKey)} '
            'period ${p.entry.periodNumber}: ${fresh.reasons.join(' ')}',
          );
        }
        final sub = Substitution(
          substitutionId: p.substitutionId,
          schoolId: tt.schoolId,
          branchId: tt.branchId,
          academicYearId: tt.year.academicYearId,
          dateKey: p.dateKey,
          timetableId: p.timetable.timetableId,
          timetableVersion: p.timetable.version,
          entryId: p.entry.entryId,
          slotId: p.entry.slotId,
          weekday: p.entry.weekday,
          periodNumber: p.entry.periodNumber,
          startMin: p.entry.startMin,
          endMin: p.entry.endMin,
          classId: p.timetable.classId,
          sectionId: p.timetable.sectionId,
          classLabel: p.timetable.title,
          subjectId: p.entry.subjectId,
          subjectName: p.entry.subjectName,
          originalTeacherId: p.entry.teacherStaffId,
          originalTeacherName: p.entry.teacherName,
          substituteTeacherId: c.staff.staffId,
          substituteTeacherName: c.staff.name,
          reasonKind: _kind,
          reason: _reason.text.trim().isEmpty
              ? _kind.displayName
              : _reason.text.trim(),
          leaveApplicationId: _kind == SubstitutionReasonKind.leave
              ? _leaveFor[p.substitutionId]
              : null,
        );
        await repo.assign(
          substitution: sub,
          expectedSequence: seq,
          recipients: _recipients(sub, teachers, actorUserId: tt.userId),
          actor: _actor,
        );
        done++;
      }
      ref.invalidate(substitutionsRangeProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$done cover${done == 1 ? '' : 's'} arranged.')),
      );
      context.go('/timetable/substitutions');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = [
            if (done > 0) '$done cover(s) were arranged before this stopped.',
            e is StateError ? e.message : userMessageFor(e),
          ].join(' '),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final theme = Theme.of(context);
    final teachers = ref.watch(activeTeachersProvider(tt.branchKey));
    final leave =
        ref
            .watch(
              staffLeaveRangeProvider((
                schoolId: tt.schoolId,
                branchId: tt.branchId,
                fromKey: _from,
                toKey: _to,
              )),
            )
            .value ??
        const <LeaveCalendarEntry>[];
    final onLeaveIds = {for (final l in leave) l.subjectId};

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: DropdownButtonFormField<String>(
                value: _teacher,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Teacher being covered',
                  isDense: true,
                ),
                items: [
                  for (final t in teachers.value ?? const <StaffLite>[])
                    DropdownMenuItem(
                      value: t.staffId,
                      child: Text(
                        onLeaveIds.contains(t.staffId)
                            ? '${t.name} (approved leave)'
                            : t.name,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _teacher = v;
                  _affected = null;
                }),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.event),
              label: Text('From ${ttDate(_from)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.event_available),
              label: Text('To ${ttDate(_to)}'),
            ),
            FilledButton.icon(
              onPressed: _busy || _teacher == null ? null : _find,
              icon: const Icon(Icons.search),
              label: const Text('Find affected periods'),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (_affected != null) ...[
          if (_affected!.isEmpty)
            const EmptyView(
              icon: Icons.event_available_outlined,
              message: 'This teacher has no scheduled periods in that range.',
            )
          else ...[
            Text(
              '${_affected!.length} affected period${_affected!.length == 1 ? '' : 's'}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final p in _affected!)
              _PeriodCard(
                period: p,
                candidates: _candidates[p.substitutionId] ?? const [],
                chosen: _chosen[p.substitutionId],
                onChanged: (v) => setState(() => _chosen[p.substitutionId] = v),
              ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<SubstitutionReasonKind>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final k in SubstitutionReasonKind.values)
                  DropdownMenuItem(value: k, child: Text(k.displayName)),
              ],
              onChanged: (v) =>
                  setState(() => _kind = v ?? SubstitutionReasonKind.other),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reason,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                helperText:
                    'Avoid private details: this appears in covers and notices.',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                icon: const Icon(Icons.check),
                label: const Text('Review and confirm'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final AffectedPeriod period;
  final List<SubstituteCandidate> candidates;
  final String? chosen;
  final ValueChanged<String?> onChanged;

  const _PeriodCard({
    required this.period,
    required this.candidates,
    required this.chosen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = period;
    final eligible = candidates.where((c) => c.eligible).toList();
    final blocked = candidates.where((c) => !c.eligible).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ttDate(p.dateKey)} · P${p.entry.periodNumber} '
              '${p.entry.timeLabel} · ${p.timetable.title}',
              style: theme.textTheme.titleSmall,
            ),
            Text(p.entry.subjectName),
            const SizedBox(height: AppSpacing.sm),
            if (p.isCovered)
              Text(
                'Already covered by ${p.existing!.substituteTeacherName}.',
                style: theme.textTheme.bodySmall,
              )
            else if (eligible.isEmpty)
              Text(
                'Nobody is free and qualified for this period.',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else
              DropdownButtonFormField<String?>(
                value: chosen,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Substitute',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No substitute yet'),
                  ),
                  for (final c in eligible)
                    DropdownMenuItem(
                      value: c.staff.staffId,
                      child: Text(
                        '${c.staff.name}'
                        '${c.teachesSubject
                            ? ' · teaches ${p.entry.subjectName}'
                            : c.teachesClass
                            ? ' · teaches this class'
                            : ''}',
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            if (blocked.isNotEmpty && !p.isCovered)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '${blocked.length} not available',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  for (final c in blocked)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.staff.name),
                      subtitle: Text(c.reasons.join(' ')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ history

/// `/timetable/history` — publications, withdrawals and replacements (the
/// version history), newest first.
class TimetableHistoryPage extends StatelessWidget {
  const TimetableHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timetable history')),
      body: TimetableScope(builder: (context, tt) => _History(tt: tt)),
    );
  }
}

class _History extends ConsumerWidget {
  final TimetableContext tt;

  const _History({required this.tt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(timetableHistoryProvider(tt.yearKey));
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(timetableHistoryProvider(tt.yearKey)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.history,
            message: 'No timetable activity yet for this year.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final h = list[i];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${h.title} · v${h.version} · ${h.event.wireValue.toLowerCase()}',
              ),
              subtitle: Text(
                [
                  h.actorName,
                  if ((h.note ?? '').isNotEmpty) h.note!,
                ].join(' · '),
              ),
              trailing: h.at == null
                  ? null
                  : Text(ttDate(AttendanceDate.key(h.at!))),
              onTap: () => context.go('/timetable/editor/${h.timetableId}'),
            );
          },
        );
      },
    );
  }
}
