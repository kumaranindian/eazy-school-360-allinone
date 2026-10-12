import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../domain/timetable.dart';
import '../../domain/timetable_enums.dart';
import '../../domain/timetable_validation.dart';
import '../providers/timetable_providers.dart';
import '../widgets/issue_list.dart';
import '../widgets/timetable_format.dart';
import '../widgets/timetable_scope.dart';

/// `/timetable/conflicts` — checks every published and draft timetable of the
/// year against the others and against approved leave, and lists what is in
/// conflict. Published timetables should never conflict (publishing refuses
/// it); this finds anything that slipped in through a changed assignment,
/// leave, or schedule.
class TimetableConflictsPage extends StatelessWidget {
  const TimetableConflictsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conflict report')),
      body: TimetableScope(builder: (context, tt) => _Conflicts(tt: tt)),
    );
  }
}

class _Result {
  final Timetable timetable;
  final List<TimetableIssue> issues;

  const _Result(this.timetable, this.issues);
}

class _Conflicts extends ConsumerWidget {
  final TimetableContext tt;

  const _Conflicts({required this.tt});

  Future<List<_Result>> _run(WidgetRef ref) async {
    final all = await readAlive(ref, timetablesProvider(tt.yearKey));
    final published = await readAlive(
      ref,
      publishedBundlesProvider(tt.yearKey),
    );
    final sets = {
      for (final s in await readAlive(ref, periodSetsProvider(tt.yearKey)))
        s.periodSetId: s,
    };
    final assignments = await readAlive(
      ref,
      yearAssignmentsProvider(tt.yearKey),
    );
    final teachers = await readAlive(ref, activeTeachersProvider(tt.branchKey));
    final working = await readAlive(ref, workingDaysProvider(tt.branchKey));
    final leave = await readAlive(
      ref,
      staffLeaveRangeProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        fromKey: tt.yearStartKey,
        toKey: tt.yearEndKey,
      )),
    );
    final repo = ref.read(timetableRepositoryProvider);
    final results = <_Result>[];
    for (final t in all) {
      if (t.status == TimetableStatus.archived) continue;
      final entries = t.isPublished
          ? published
                    .where((b) => b.timetable.timetableId == t.timetableId)
                    .firstOrNull
                    ?.entries ??
                const <TimetableEntry>[]
          : await repo.fetchEntries(tt.schoolId, tt.branchId, t.timetableId);
      final issues = TimetableValidator.validate(
        candidate: TimetableBundle(t, entries),
        periodSets: sets,
        workingWeekdays: {
          for (final e in working.isWorkingDay.entries)
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
      results.add(_Result(t, issues));
    }
    return results;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<_Result>>(
      future: _run(ref),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: userMessageFor(snap.error!));
        }
        final results = snap.data!;
        if (results.isEmpty) {
          return const EmptyView(
            icon: Icons.rule,
            message: 'No draft or published timetables to check.',
          );
        }
        final withIssues = results.where((r) => r.issues.isNotEmpty).toList();
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              withIssues.isEmpty
                  ? 'No conflicts across ${results.length} timetable(s).'
                  : '${withIssues.length} of ${results.length} timetable(s) have findings.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final r in withIssues)
              Card(
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
                              '${r.timetable.title} · v${r.timetable.version} · '
                              '${r.timetable.status.displayName} · ${ttRange(r.timetable)}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go(
                              '/timetable/editor/${r.timetable.timetableId}',
                            ),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      IssueList(issues: r.issues),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
