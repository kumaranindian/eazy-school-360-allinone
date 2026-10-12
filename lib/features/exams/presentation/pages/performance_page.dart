import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/examination.dart';
import '../../domain/result_calculator.dart';
import '../../domain/result_summary.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams/performance` — academic performance of one examination.
///
/// Definitions (also in the milestone doc):
/// * **Pass rate** = students with an overall PASS ÷ students with a PASS or
///   FAIL (not applicable results are left out).
/// * **Average** = mean of the students' overall percentages (students
///   without one are left out).
/// * **Subject average / pass rate** use entered marks only; absent and
///   exempted students are counted separately, never as zero.
/// * **Needs support** = overall FAIL, or any failed subject.
/// * Examinations are never compared with each other here: schemes and
///   maxima differ. Ranks appear only on results of a scheme that enables
///   them.
class PerformancePage extends ConsumerWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Academic performance')),
      body: TimetableScope(builder: (context, tt) => _Performance(tt: tt)),
    );
  }
}

final _examChoicesProvider = FutureProvider.autoDispose
    .family<
      List<Examination>,
      ({String schoolId, String branchId, String yearId})
    >((ref, k) async {
      final repo = ref.read(examRepositoryProvider);
      final out = <Examination>[];
      Object? cursor;
      var pages = 0;
      do {
        final page = await repo.fetch(
          schoolId: k.schoolId,
          branchId: k.branchId,
          academicYearId: k.yearId,
          pageSize: 50,
          cursor: cursor,
        );
        out.addAll(page.items);
        cursor = page.nextCursor;
        pages++;
      } while (cursor != null && pages < 6);
      return out;
    });

class _Performance extends ConsumerStatefulWidget {
  final TimetableContext tt;
  const _Performance({required this.tt});

  @override
  ConsumerState<_Performance> createState() => _PerformanceState();
}

class _PerformanceState extends ConsumerState<_Performance> {
  String? _examId;

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final isManager = tt.tenant.can(Permission.approveResults);
    final exams = ref.watch(
      _examChoicesProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        yearId: tt.year.academicYearId,
      )),
    );
    return exams.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (all) {
        // Managers see finalised and published; teachers only published
        // (what the rules let them read).
        final usable = [
          for (final e in all)
            if (e.status == ExamStatus.published ||
                (isManager &&
                    (e.status == ExamStatus.completed &&
                        e.resultsWritten == e.resultCount &&
                        e.resultCount > 0)))
              e,
        ];
        if (usable.isEmpty) {
          return const EmptyView(
            icon: Icons.insights_outlined,
            message:
                'Performance appears here once an examination of this '
                'academic year has been finalised or published.',
          );
        }
        final selected = usable.firstWhere(
          (e) => e.examId == _examId,
          orElse: () => usable.first,
        );
        return PageColumn(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              DropdownButtonFormField<String>(
                value: selected.examId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Examination',
                  isDense: true,
                ),
                items: [
                  for (final e in usable)
                    DropdownMenuItem(
                      value: e.examId,
                      child: Text('${e.name} · ${e.classLabel ?? e.classId}'),
                    ),
                ],
                onChanged: (v) => setState(() => _examId = v),
              ),
              const SizedBox(height: AppSpacing.md),
              _ExamStatsView(
                key: ValueKey(selected.examId),
                tt: tt,
                exam: selected,
                isManager: isManager,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExamStatsView extends ConsumerWidget {
  final TimetableContext tt;
  final Examination exam;
  final bool isManager;

  const _ExamStatsView({
    super.key,
    required this.tt,
    required this.exam,
    required this.isManager,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: exam.schoolId,
      branchId: exam.branchId,
      examId: exam.examId,
    );
    final stored = ref.watch(storedResultsProvider(key));
    Set<String>? mySubjects;
    if (!isManager) {
      final staff = ref
          .watch(
            ownStaffProvider((
              schoolId: exam.schoolId,
              branchId: exam.branchId,
              userId: tt.userId,
            )),
          )
          .value;
      final facts = ref
          .watch(
            yearAssignmentsProvider((
              schoolId: exam.schoolId,
              branchId: exam.branchId,
              academicYearId: exam.academicYearId,
            )),
          )
          .value;
      mySubjects = {
        for (final f in facts ?? const [])
          if (staff != null &&
              f.teacherStaffId == staff.staffId &&
              f.classId == exam.classId &&
              f.subjectId != null)
            f.subjectId!,
      };
    }
    return stored.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(storedResultsProvider(key)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.hourglass_empty,
            message: 'No results have been stored for this examination yet.',
          );
        }
        final results = [for (final s in list) s.result];
        final stats = ExamStats.of(results);
        final grades = stats.gradeDistribution.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final subjectRows = [
          for (final e in stats.bySubject.entries)
            if (mySubjects == null || mySubjects.contains(e.key)) e,
        ];
        final support = isManager
            ? [
                for (final s in list)
                  if (s.result.result == OverallResult.fail ||
                      s.result.lines.any(
                        (l) => l.outcome == SubjectOutcome.failed,
                      ))
                    s,
              ]
            : const <ResultSummary>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                CountTile(
                  label: 'Students',
                  value: stats.students,
                  icon: Icons.groups,
                ),
                CountTileText(
                  label: 'Pass rate',
                  value: stats.passRate == null
                      ? '–'
                      : '${fmtNum(stats.passRate, decimals: 1)}%',
                ),
                CountTileText(
                  label: 'Average',
                  value: stats.averagePercentage == null
                      ? '–'
                      : '${fmtNum(stats.averagePercentage, decimals: 1)}%',
                ),
                CountTile(
                  label: 'Failed',
                  value: stats.failed,
                  icon: Icons.close,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: 'Grade distribution',
              child: grades.isEmpty
                  ? const Text('No grades yet.')
                  : Column(
                      children: [
                        for (final g in grades)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(width: 48, child: Text(g.key)),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: g.value / stats.students,
                                    minHeight: 10,
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    '${g.value}',
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            SectionCard(
              title: isManager ? 'Subjects' : 'Your subjects',
              child: subjectRows.isEmpty
                  ? const Text('No subjects to show.')
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Subject')),
                          DataColumn(label: Text('Average %'), numeric: true),
                          DataColumn(label: Text('Pass rate'), numeric: true),
                          DataColumn(label: Text('Failed'), numeric: true),
                          DataColumn(label: Text('Absent'), numeric: true),
                        ],
                        rows: [
                          for (final e in subjectRows)
                            DataRow(
                              cells: [
                                DataCell(Text(e.value.name)),
                                DataCell(
                                  Text(
                                    fmtNum(
                                      e.value.averagePercentage,
                                      decimals: 1,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    e.value.passRate == null
                                        ? '–'
                                        : '${fmtNum(e.value.passRate, decimals: 1)}%',
                                  ),
                                ),
                                DataCell(Text('${e.value.failed}')),
                                DataCell(Text('${e.value.absent}')),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
            if (isManager)
              SectionCard(
                title: 'Students who may need academic support',
                child: support.isEmpty
                    ? const Text('No student failed a subject.')
                    : Column(
                        children: [
                          for (final s in support)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(s.result.studentName),
                              subtitle: Text(
                                [
                                  for (final l in s.result.lines)
                                    if (l.outcome == SubjectOutcome.failed)
                                      l.subjectName,
                                ].join(', '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.go(
                                AppRoutes.examStudentResult
                                    .replaceFirst(':examId', exam.examId)
                                    .replaceFirst(':studentId', s.studentId),
                              ),
                            ),
                        ],
                      ),
              ),
            Text(
              'Pass rate = passed ÷ (passed + failed). Averages use entered '
              'marks only; absent and exempted students are not counted as '
              'zero. Version ${exam.resultVersion} of the result, graded with '
              '"${exam.schemeSnapshot?['name'] ?? 'the school scheme'}".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
