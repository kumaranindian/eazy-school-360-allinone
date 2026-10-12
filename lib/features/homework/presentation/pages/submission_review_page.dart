import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_repositories.dart' show HomeworkActor;
import '../../domain/homework_rules.dart';
import '../../domain/homework_submission.dart';
import '../providers/homework_providers.dart';
import '../widgets/homework_widgets.dart';

/// `/homework/review/:homeworkId/:studentId` — one student's work, its
/// history, and the review actions: grade, return for revision, mark
/// reviewed. Every action appends a revision and is attributed to the
/// reviewer; nothing overwrites earlier work.
class SubmissionReviewPage extends ConsumerWidget {
  final String homeworkId;
  final String studentId;

  const SubmissionReviewPage({
    super.key,
    required this.homeworkId,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submission')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final hwKey = (
            schoolId: schoolId,
            branchId: branchId,
            homeworkId: homeworkId,
          );
          final subKey = (
            schoolId: schoolId,
            branchId: branchId,
            submissionId: HomeworkSubmission.idFor(homeworkId, studentId),
          );
          final hw = ref.watch(homeworkProvider(hwKey));
          final sub = ref.watch(submissionProvider(subKey));
          if (hw.isLoading || sub.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (hw.hasError || sub.hasError) {
            return ErrorView(
              message: userMessageFor((hw.error ?? sub.error)!),
              onRetry: () {
                ref.invalidate(homeworkProvider(hwKey));
                ref.invalidate(submissionProvider(subKey));
              },
            );
          }
          final h = hw.value;
          final s = sub.value;
          if (h == null || s == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This submission could not be found.',
            );
          }
          return _Review(
            homework: h,
            submission: s,
            subKey: subKey,
            actor: actorFor(tenant),
          );
        },
      ),
    );
  }
}

class _Review extends ConsumerStatefulWidget {
  final Homework homework;
  final HomeworkSubmission submission;
  final SubmissionKey subKey;
  final HomeworkActor actor;

  const _Review({
    required this.homework,
    required this.submission,
    required this.subKey,
    required this.actor,
  });

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  final _marks = TextEditingController();
  final _feedback = TextEditingController();
  bool _busy = false;
  String? _error;
  int? _seededRevision;

  @override
  void initState() {
    super.initState();
    _seed(widget.submission);
  }

  @override
  void didUpdateWidget(covariant _Review oldWidget) {
    super.didUpdateWidget(oldWidget);
    _seed(widget.submission);
  }

  @override
  void dispose() {
    _marks.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _seed(HomeworkSubmission s) {
    if (_seededRevision == s.revision) return;
    _seededRevision = s.revision;
    _marks.text = s.marks?.toString() ?? '';
    _feedback.text = s.status == SubmissionStatus.returnedForRevision
        ? ''
        : (s.feedback ?? '');
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.homework;
    final s = widget.submission;
    final repo = ref.read(submissionRepositoryProvider);
    final revisions = ref.watch(submissionRevisionsProvider(widget.subKey));
    final open =
        h.status == HomeworkStatus.published ||
        h.status == HomeworkStatus.closed;
    final withStudent = s.status == SubmissionStatus.returnedForRevision;
    final canReviewNow = open && !withStudent;
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(s.studentName, style: Theme.of(context).textTheme.titleLarge),
          Text('${h.title} · ${h.subjectName} · ${h.classLabel ?? h.classId}'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SubmissionStatusPill(s.status, late: s.late),
              if (s.late)
                StatusPill(
                  label: 'Handed in after the deadline',
                  icon: Icons.schedule,
                  color: Theme.of(context).colorScheme.error,
                ),
              Text('Last handed in ${formatInstant(s.submittedAt)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Answer',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  s.textAnswer.isEmpty ? 'No written answer.' : s.textAnswer,
                ),
                if (s.attachments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AttachmentList(attachments: s.attachments),
                ],
              ],
            ),
          ),
          if (s.feedback != null || s.marks != null)
            SectionCard(
              title: 'Current feedback',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.marks != null)
                    Text(
                      h.maxMarks == null
                          ? 'Marks: ${s.marks}'
                          : 'Marks: ${s.marks} / ${h.maxMarks}',
                    ),
                  if (s.feedback != null) Text(s.feedback!),
                  if (s.gradedByName != null)
                    Text(
                      'By ${s.gradedByName} · ${formatInstant(s.gradedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          if (!open)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('This homework is archived'),
                subtitle: Text('Submissions can no longer be reviewed.'),
              ),
            )
          else if (withStudent)
            const Card(
              child: ListTile(
                leading: Icon(Icons.hourglass_empty),
                title: Text('Waiting for the student'),
                subtitle: Text(
                  'You returned this for revision. It can be reviewed again '
                  'after it is resubmitted.',
                ),
              ),
            )
          else
            SectionCard(
              title: 'Review',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (h.maxMarks != null)
                    TextField(
                      controller: _marks,
                      keyboardType: TextInputType.number,
                      enabled: canReviewNow && !_busy,
                      decoration: InputDecoration(
                        labelText: 'Marks (0 – ${h.maxMarks})',
                      ),
                    ),
                  TextField(
                    controller: _feedback,
                    enabled: canReviewNow && !_busy,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Feedback',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                final marks = h.maxMarks == null
                                    ? null
                                    : int.tryParse(_marks.text.trim());
                                final problem = HomeworkRules.checkGrade(
                                  homework: h,
                                  submission: s,
                                  marks: marks,
                                  feedback: _feedback.text,
                                );
                                if (problem != null) {
                                  setState(() => _error = problem);
                                  return;
                                }
                                _act(
                                  () => repo.grade(
                                    homework: h,
                                    current: s,
                                    marks: marks,
                                    feedback: _feedback.text,
                                    actor: widget.actor,
                                  ),
                                  'Graded. The family has been notified.',
                                );
                              },
                        icon: const Icon(Icons.check),
                        label: Text(s.isGraded ? 'Update grade' : 'Grade'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                final problem = HomeworkRules.checkReturn(
                                  submission: s,
                                  feedback: _feedback.text,
                                );
                                if (problem != null) {
                                  setState(() => _error = problem);
                                  return;
                                }
                                _act(
                                  () => repo.returnForRevision(
                                    homework: h,
                                    current: s,
                                    feedback: _feedback.text,
                                    actor: widget.actor,
                                  ),
                                  'Returned for revision.',
                                );
                              },
                        icon: const Icon(Icons.undo),
                        label: const Text('Return for revision'),
                      ),
                      if (s.status == SubmissionStatus.submitted ||
                          s.status == SubmissionStatus.lateSubmitted)
                        TextButton.icon(
                          onPressed: _busy || s.reviewedBy != null
                              ? null
                              : () => _act(
                                  () => repo.markReviewed(
                                    homework: h,
                                    current: s,
                                    actor: widget.actor,
                                  ),
                                  'Marked as reviewed.',
                                ),
                          icon: const Icon(Icons.done_all),
                          label: Text(
                            s.reviewedBy != null
                                ? 'Reviewed'
                                : 'Mark as reviewed',
                          ),
                        ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          SectionCard(
            title: 'History',
            child: revisions.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) => RevisionTimeline(revisions: list, homework: h),
            ),
          ),
        ],
      ),
    );
  }
}

/// Append-only history of a submission: what was handed in, returned,
/// graded, and by whom. Shared by teachers and families.
class RevisionTimeline extends StatelessWidget {
  final List<SubmissionRevision> revisions;
  final Homework homework;

  const RevisionTimeline({
    super.key,
    required this.revisions,
    required this.homework,
  });

  static String _label(SubmissionEvent e) => switch (e) {
    SubmissionEvent.submit => 'Handed in',
    SubmissionEvent.resubmit => 'Resubmitted',
    SubmissionEvent.returnForRevision => 'Returned for revision',
    SubmissionEvent.grade => 'Graded',
    SubmissionEvent.review => 'Marked reviewed',
  };

  @override
  Widget build(BuildContext context) {
    if (revisions.isEmpty) return const Text('No history yet.');
    return Column(
      children: [
        for (final r in revisions.reversed)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.history, size: 20),
            title: Text(_label(r.event)),
            subtitle: Text('${r.actorName} · ${formatInstant(r.at)}'),
            childrenPadding: const EdgeInsets.only(
              left: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.textAnswer.isNotEmpty) SelectableText(r.textAnswer),
              if (r.attachments.isNotEmpty)
                AttachmentList(attachments: r.attachments),
              if (r.marks != null)
                Text(
                  homework.maxMarks == null
                      ? 'Marks: ${r.marks}'
                      : 'Marks: ${r.marks} / ${homework.maxMarks}',
                ),
              if (r.feedback != null) Text('Feedback: ${r.feedback}'),
            ],
          ),
      ],
    );
  }
}
