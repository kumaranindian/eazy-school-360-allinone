import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../students/domain/student.dart';
import '../../domain/file_attachment.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_repositories.dart';
import '../../domain/homework_rules.dart';
import '../../domain/homework_submission.dart';
import '../providers/homework_providers.dart';
import '../widgets/family_scope.dart';
import '../widgets/homework_widgets.dart';
import 'submission_review_page.dart' show RevisionTimeline;

/// `/my-homework/:homeworkId/:studentId` — the instructions, the child's
/// submission (and its history), teacher feedback and marks, and the form to
/// hand work in or resubmit.
///
/// Opening this page records nothing: only an explicit, confirmed submit
/// does. The submission has one deterministic id, so a double tap or a
/// retry cannot create a second one; a family can never write marks or
/// feedback (the rules refuse those fields).
class MyHomeworkDetailPage extends StatelessWidget {
  final String homeworkId;
  final String studentId;

  const MyHomeworkDetailPage({
    super.key,
    required this.homeworkId,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Homework')),
      body: FamilyScope(
        builder: (context, tenant, children, _) {
          final child = children.where((c) => c.studentId == studentId);
          if (child.isEmpty) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message: 'This child is not linked to your account.',
            );
          }
          return _Detail(
            homeworkId: homeworkId,
            child: child.first,
            actor: actorFor(tenant),
          );
        },
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  final String homeworkId;
  final Student child;
  final HomeworkActor actor;

  const _Detail({
    required this.homeworkId,
    required this.child,
    required this.actor,
  });

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  final _text = TextEditingController();
  List<FileAttachment> _files = [];
  bool _busy = false;
  bool _editing = false;
  String? _error;
  int? _seededRevision;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _seedFrom(HomeworkSubmission? s) {
    final rev = s?.revision ?? 0;
    if (_seededRevision == rev) return;
    _seededRevision = rev;
    _text.text = s?.textAnswer ?? '';
    _files = [...?s?.attachments];
    _editing = false;
  }

  Future<void> _addFile(Homework h) async {
    final remaining = 3 - _files.length;
    final files = await pickValidatedFiles(
      remaining: remaining,
      onProblem: (m) {
        if (mounted) setState(() => _error = m);
      },
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final f in files) {
        final uploaded = await ref
            .read(homeworkFileStoreProvider)
            .upload(
              path: HomeworkPaths.submissionFile(
                h.schoolId,
                h.branchId,
                h.homeworkId,
                widget.child.studentId,
                uniqueFileName(f.name),
              ),
              fileName: f.name,
              bytes: f.bytes,
              uploadedBy: widget.actor.userId,
            );
        _files.add(uploaded);
      }
    } catch (e) {
      _error = userMessageFor(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(Homework h, HomeworkSubmission? current) async {
    if (_busy) return;
    final content = HomeworkRules.checkContent(
      homework: h,
      text: _text.text,
      attachmentCount: _files.length,
    );
    if (content != null) return setState(() => _error = content);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          current == null ? 'Hand in this homework?' : 'Resubmit this work?',
        ),
        content: Text(
          current == null
              ? 'Your teacher will see your answer'
                    '${h.allowResubmission ? ', and you can change it until the deadline' : ''}.'
              : 'Your earlier answer stays in the history; the teacher '
                    'sees this version.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(current == null ? 'Hand in' : 'Resubmit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(submissionRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (current == null) {
        await repo.submit(
          homework: h,
          studentId: widget.child.studentId,
          studentName: widget.child.displayName,
          text: _text.text,
          attachments: _files,
          actor: widget.actor,
        );
      } else {
        await repo.resubmit(
          homework: h,
          current: current,
          text: _text.text,
          attachments: _files,
          actor: widget.actor,
        );
      }
      if (!mounted) return;
      setState(() => _editing = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Handed in. Your teacher can see it now.'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    final hwKey = (
      schoolId: c.schoolId,
      branchId: c.branchId,
      homeworkId: widget.homeworkId,
    );
    final subKey = (
      schoolId: c.schoolId,
      branchId: c.branchId,
      submissionId: HomeworkSubmission.idFor(widget.homeworkId, c.studentId),
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
    // A homework the child's section does not own is not shown: the
    // placement check keeps a transferred child from other sections' work.
    if (h == null ||
        !h.status.isVisibleToFamilies ||
        h.classId != c.currentClassId ||
        h.sectionId != c.currentSectionId) {
      return const EmptyView(
        icon: Icons.search_off,
        message: 'This homework is not available.',
      );
    }
    final s = sub.value;
    _seedFrom(s);
    final now = DateTime.now();
    final state = HomeworkRules.familyState(
      homework: h,
      submission: s,
      now: now,
    );
    final revisions = s == null
        ? null
        : ref.watch(submissionRevisionsProvider(subKey));

    // What the family may do now.
    String? blocked;
    var canSubmit = false;
    if (!h.requiresSubmission) {
      blocked = 'This homework does not need a submission.';
    } else if (s == null) {
      final d = HomeworkRules.checkSubmit(homework: h, now: now);
      blocked = d.error;
      canSubmit = d.error == null;
    } else {
      final d = HomeworkRules.checkResubmit(homework: h, current: s, now: now);
      blocked = d.error;
      canSubmit = d.error == null;
    }

    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(children: [FamilyStatePill(state)]),
          const SizedBox(height: AppSpacing.sm),
          HomeworkContent(homework: h),
          if (s != null && (s.feedback != null || s.marks != null))
            SectionCard(
              title: s.status == SubmissionStatus.returnedForRevision
                  ? 'Teacher feedback — please revise'
                  : 'Teacher feedback',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.marks != null)
                    Text(
                      h.maxMarks == null
                          ? 'Marks: ${s.marks}'
                          : 'Marks: ${s.marks} / ${h.maxMarks}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (s.feedback != null) SelectableText(s.feedback!),
                  if (s.gradedByName != null)
                    Text(
                      '${s.gradedByName} · ${formatInstant(s.gradedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          if (h.requiresSubmission)
            SectionCard(
              title: 'Your submission',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s != null) ...[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SubmissionStatusPill(s.status, late: s.late),
                        Text('Handed in ${formatInstant(s.submittedAt)}'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (s != null && !_editing) ...[
                    SelectableText(
                      s.textAnswer.isEmpty
                          ? 'No written answer.'
                          : s.textAnswer,
                    ),
                    AttachmentList(attachments: s.attachments, emptyLabel: ''),
                    const SizedBox(height: AppSpacing.sm),
                    if (canSubmit)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _editing = true),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(
                          s.status == SubmissionStatus.returnedForRevision
                              ? 'Revise and resubmit'
                              : 'Change and resubmit',
                        ),
                      )
                    else if (blocked != null)
                      Text(
                        blocked,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ] else if (canSubmit) ...[
                    TextField(
                      controller: _text,
                      enabled: !_busy,
                      minLines: 4,
                      maxLines: 12,
                      maxLength: 5000,
                      decoration: const InputDecoration(
                        labelText: 'Your answer',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (h.allowFiles) ...[
                      AttachmentList(
                        attachments: _files,
                        emptyLabel: 'No files attached',
                        onRemove: _busy
                            ? null
                            : (f) => setState(() => _files.remove(f)),
                      ),
                      TextButton.icon(
                        onPressed: _busy || _files.length >= 3
                            ? null
                            : () => _addFile(h),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Attach a file'),
                      ),
                      Text(
                        'PDF, JPG, PNG, TXT or DOCX, up to 10 MB, at most 3 '
                        'files.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
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
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _submit(h, s),
                          icon: const Icon(Icons.send),
                          label: Text(s == null ? 'Hand in' : 'Resubmit'),
                        ),
                        if (s != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _seededRevision = null;
                                    _seedFrom(s);
                                  }),
                            child: const Text('Cancel'),
                          ),
                        ],
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
                  ] else
                    Text(blocked ?? 'Submission is not open.'),
                ],
              ),
            ),
          if (revisions != null && (revisions.value?.length ?? 0) > 1)
            SectionCard(
              title: 'History',
              child: RevisionTimeline(revisions: revisions.value!, homework: h),
            ),
        ],
      ),
    );
  }
}
