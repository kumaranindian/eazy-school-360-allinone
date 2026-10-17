import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/family_scope.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../students/domain/student.dart';
import '../../../students/domain/student_status.dart';
import '../../domain/examination.dart';
import '../../domain/result_summary.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';
import '../widgets/report_card_loader.dart';

/// `/my-results` — a parent's view of a linked child's **published** results:
/// the examinations of the child's class and section, the result in force
/// for each, and — only between examinations graded by the *same* scheme —
/// how the percentage moved.
class MyResultsPage extends StatelessWidget {
  const MyResultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('Results')),
      body: FamilyScope(
        builder: (context, tenant, children, child) =>
            _ChildResults(child: child),
      ),
    );
  }
}

typedef _Row = ({Examination exam, ResultSummary? result, Object? error});

final _childRowsProvider = FutureProvider.autoDispose
    .family<List<_Row>, Student>((ref, child) async {
      final year = child.currentAcademicYearId;
      final classId = child.currentClassId;
      if (year == null || classId == null) return const [];
      final exams = await ref.watch(
        publishedExamsProvider((
          schoolId: child.schoolId,
          branchId: child.branchId,
          academicYearId: year,
          classId: classId,
          sectionId: child.currentSectionId,
        )).future,
      );
      final mine = [
        for (final e in exams)
          if (e.sectionId == null || e.sectionId == child.currentSectionId) e,
      ];
      final repo = ref.read(resultRepositoryProvider);
      final rows = <_Row>[];
      for (final e in mine) {
        ResultSummary? r;
        Object? failure;
        try {
          r = await repo.fetchResult(
            schoolId: child.schoolId,
            branchId: child.branchId,
            examId: e.examId,
            studentId: child.studentId,
            version: e.resultVersion,
          );
        } catch (error) {
          // Not "no result": a failed read is reported as such below.
          failure = error;
        }
        rows.add((exam: e, result: r, error: failure));
      }
      return rows;
    });

class _ChildResults extends ConsumerWidget {
  final Student child;
  const _ChildResults({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (child.status != StudentStatus.active) {
      return const EmptyView(
        icon: Icons.info_outline,
        message:
            'This child is not currently enrolled, so there are no current '
            'results to show.',
      );
    }
    if (child.currentClassId == null) {
      return const EmptyView(
        icon: Icons.class_outlined,
        message: 'This child has not been placed in a class yet.',
      );
    }
    final rows = ref.watch(_childRowsProvider(child));
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorView(
        message: userMessageFor(err),
        onRetry: () => ref.invalidate(_childRowsProvider(child)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.workspace_premium_outlined,
            message: 'No results have been published yet.',
          );
        }
        // Trend: only exams graded by the same scheme are comparable.
        final scored = [
          for (final r in list)
            if (r.result?.result.overallPercentage != null) r,
        ];
        final groups = <String, List<_Row>>{};
        for (final r in scored) {
          groups.putIfAbsent(r.exam.schemeId, () => []).add(r);
        }
        final comparable = groups.values.where((g) => g.length > 1).toList();
        return PageColumn(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              for (final r in list)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    title: Text(r.exam.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: r.error != null
                          ? Text(
                              'Could not load this result. '
                              '${userMessageFor(r.error!)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : r.result == null
                          ? const Text('Result not available yet.')
                          : Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  r.result!.result.overallPercentage == null
                                      ? '–'
                                      : '${fmtNum(r.result!.result.overallPercentage)}%',
                                ),
                                if (r.result!.result.overallGrade != null)
                                  Text(
                                    'Grade ${r.result!.result.overallGrade}',
                                  ),
                                OverallPill(r.result!.result.result),
                                if (r.result!.result.rank != null)
                                  Text(
                                    'Rank ${r.result!.result.rank} of '
                                    '${r.result!.result.classSize}',
                                  ),
                              ],
                            ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      AppRoutes.myResult
                          .replaceFirst(':examId', r.exam.examId)
                          .replaceFirst(':studentId', child.studentId),
                    ),
                  ),
                ),
              for (final g in comparable)
                SectionCard(
                  title: 'Progress between examinations',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r
                          in (g..sort(
                            (a, b) => a.exam.startDateKey.compareTo(
                              b.exam.startDateKey,
                            ),
                          )))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(r.exam.name)),
                              SizedBox(
                                width: 140,
                                child: LinearProgressIndicator(
                                  value:
                                      (r.result!.result.overallPercentage! /
                                              100)
                                          .clamp(0, 1),
                                  minHeight: 8,
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  '${fmtNum(r.result!.result.overallPercentage, decimals: 1)}%',
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        'Compared only because these examinations use the '
                        'same grading scheme.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// `/my-results/:examId/:studentId` — a published result and its report
/// card, for a linked child only.
class MyResultPage extends StatelessWidget {
  final String examId;
  final String studentId;

  const MyResultPage({
    super.key,
    required this.examId,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: FamilyScope(
        builder: (context, tenant, children, _) {
          final child = children.where((c) => c.studentId == studentId);
          if (child.isEmpty) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message: 'This child is not linked to your account.',
            );
          }
          return _ChildResult(
            examId: examId,
            child: child.first,
            schoolName: tenant.school?.name ?? '',
          );
        },
      ),
    );
  }
}

class _ChildResult extends ConsumerWidget {
  final String examId;
  final Student child;
  final String schoolName;

  const _ChildResult({
    required this.examId,
    required this.child,
    required this.schoolName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: child.schoolId,
      branchId: child.branchId,
      examId: examId,
    );
    final exam = ref.watch(examProvider(key));
    if (exam.hasError) {
      return ErrorView(
        message: userMessageFor(exam.error!),
        onRetry: () => ref.invalidate(examProvider(key)),
      );
    }
    if (!exam.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final e = exam.value;
    // Only a published examination of the child's own class and section.
    if (e == null ||
        e.classId != child.currentClassId ||
        (e.sectionId != null && e.sectionId != child.currentSectionId)) {
      return const EmptyView(
        icon: Icons.lock_outline,
        message: 'This result is not available.',
      );
    }
    final resultKey = (
      schoolId: child.schoolId,
      branchId: child.branchId,
      examId: examId,
      studentId: child.studentId,
      version: e.resultVersion,
    );
    final result = ref.watch(childResultProvider(resultKey));
    return result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorView(
        message: userMessageFor(err),
        onRetry: () => ref.invalidate(childResultProvider(resultKey)),
      ),
      data: (s) => s == null
          ? const EmptyView(
              icon: Icons.hourglass_empty,
              message: 'This result is not available.',
            )
          : PageColumn(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  ReportCardLoader(
                    schoolName: schoolName,
                    branchName: '',
                    summary: s,
                    publishedAt: e.publishedAt,
                  ),
                ],
              ),
            ),
    );
  }
}
