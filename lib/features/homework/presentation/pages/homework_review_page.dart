import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../students/domain/paged_result.dart';
import '../../../students/domain/student.dart';
import '../../../students/domain/student_status.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_submission.dart';
import '../providers/homework_providers.dart';
import '../widgets/homework_widgets.dart';

/// `/homework/review/:homeworkId` — the submissions of one homework, by
/// status, paginated. "Not submitted" is derived page by page from the
/// section roster, so a large class is never loaded into memory at once.
class HomeworkReviewPage extends ConsumerWidget {
  final String homeworkId;

  const HomeworkReviewPage({super.key, required this.homeworkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review submissions')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (
            schoolId: schoolId,
            branchId: branchId,
            homeworkId: homeworkId,
          );
          return AsyncValueWidget(
            value: ref.watch(homeworkProvider(key)),
            errorMessage: userMessageFor,
            onRetry: () => ref.invalidate(homeworkProvider(key)),
            data: (h) => h == null
                ? const EmptyView(
                    icon: Icons.search_off,
                    message: 'This homework could not be found.',
                  )
                : _ReviewList(homework: h),
          );
        },
      ),
    );
  }
}

/// Filter values: a stored status, or the derived "not submitted".
enum _Filter {
  all('All handed in', null),
  submitted('Submitted', SubmissionStatus.submitted),
  late('Submitted late', SubmissionStatus.lateSubmitted),
  resubmitted('Resubmitted', SubmissionStatus.resubmitted),
  returned('Returned', SubmissionStatus.returnedForRevision),
  graded('Graded', SubmissionStatus.graded),
  notSubmitted('Not submitted', null);

  final String label;
  final SubmissionStatus? status;
  const _Filter(this.label, this.status);
}

class _ReviewList extends ConsumerStatefulWidget {
  final Homework homework;
  const _ReviewList({required this.homework});

  @override
  ConsumerState<_ReviewList> createState() => _ReviewListState();
}

class _ReviewListState extends ConsumerState<_ReviewList> {
  final _submissions = PagedListController<HomeworkSubmission>();
  final _missing = PagedListController<Student>();
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _submissions.addListener(_refresh);
    _missing.addListener(_refresh);
    _configure();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _configure() {
    final h = widget.homework;
    if (_filter == _Filter.notSubmitted) {
      final students = ref.read(studentRepositoryProvider);
      final subs = ref.read(submissionRepositoryProvider);
      _missing.fetch = (cursor) async {
        final page = await students.fetchStudentsByPlacement(
          schoolId: h.schoolId,
          branchId: h.branchId,
          academicYearId: h.academicYearId,
          classId: h.classId,
          sectionId: h.sectionId,
          pageSize: 30,
          cursor: cursor,
        );
        final active = [
          for (final s in page.items)
            if (s.status == StudentStatus.active) s,
        ];
        final done = await subs.fetchForStudents(
          schoolId: h.schoolId,
          branchId: h.branchId,
          homeworkId: h.homeworkId,
          studentIds: [for (final s in active) s.studentId],
        );
        final doneIds = {for (final d in done) d.studentId};
        return PagedResult(
          items: [
            for (final s in active)
              if (!doneIds.contains(s.studentId)) s,
          ],
          nextCursor: page.nextCursor,
        );
      };
      _missing.reload();
    } else {
      final repo = ref.read(submissionRepositoryProvider);
      _submissions.fetch = (cursor) => repo.fetchForHomework(
        schoolId: h.schoolId,
        branchId: h.branchId,
        homeworkId: h.homeworkId,
        status: _filter.status,
        cursor: cursor,
      );
      _submissions.reload();
    }
  }

  @override
  void dispose() {
    _submissions.dispose();
    _missing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.homework;
    final key = (
      schoolId: h.schoolId,
      branchId: h.branchId,
      homeworkId: h.homeworkId,
    );
    final counts = ref.watch(submissionCountsProvider(key));
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(h.title, style: Theme.of(context).textTheme.titleLarge),
          Text(
            '${h.subjectName} · ${h.classLabel ?? h.classId} · ${dueLabel(h)}',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CountTile(
                label: 'Handed in',
                value: counts.value?.submitted,
                icon: Icons.upload_file,
              ),
              CountTile(
                label: 'To review',
                value: counts.value?.awaitingReview,
                icon: Icons.rate_review_outlined,
              ),
              CountTile(
                label: 'Returned',
                value: counts.value?.returned,
                icon: Icons.undo,
              ),
              CountTile(
                label: 'Graded',
                value: counts.value?.graded,
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _configure();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_filter == _Filter.notSubmitted)
            _missingList(context)
          else
            _submissionList(context),
        ],
      ),
    );
  }

  Widget _submissionList(BuildContext context) {
    final c = _submissions;
    if (c.errorMessage != null && c.items.isEmpty) {
      return ErrorView(message: c.errorMessage!, onRetry: c.reload);
    }
    if (!c.hasLoaded) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (c.items.isEmpty) {
      return const EmptyView(
        icon: Icons.inbox_outlined,
        message: 'No submissions in this view.',
      );
    }
    return Column(
      children: [
        for (final s in c.items)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              title: Text(s.studentName),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SubmissionStatusPill(s.status),
                    Text(formatInstant(s.submittedAt)),
                    if (s.marks != null && widget.homework.maxMarks != null)
                      Text('${s.marks}/${widget.homework.maxMarks}'),
                    if (s.revision > 1) Text('${s.revision - 1} change(s)'),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(
                AppRoutes.homeworkSubmission
                    .replaceFirst(':homeworkId', s.homeworkId)
                    .replaceFirst(':studentId', s.studentId),
              ),
            ),
          ),
        _more(c.hasMore, c.isLoading, c.loadMore),
      ],
    );
  }

  Widget _missingList(BuildContext context) {
    final c = _missing;
    if (c.errorMessage != null && c.items.isEmpty) {
      return ErrorView(message: c.errorMessage!, onRetry: c.reload);
    }
    if (!c.hasLoaded) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (c.items.isEmpty && !c.hasMore) {
      return const EmptyView(
        icon: Icons.celebration_outlined,
        message: 'Every active student has handed this in.',
      );
    }
    return Column(
      children: [
        for (final s in c.items)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: const Icon(Icons.radio_button_unchecked),
              title: Text(s.displayName),
              subtitle: Text(
                s.currentRollNumber == null
                    ? 'Not submitted'
                    : 'Roll ${s.currentRollNumber} · Not submitted',
              ),
            ),
          ),
        _more(c.hasMore, c.isLoading, c.loadMore),
      ],
    );
  }

  Widget _more(bool hasMore, bool loading, VoidCallback onMore) {
    if (!hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : OutlinedButton(onPressed: onMore, child: const Text('Load more')),
      ),
    );
  }
}
