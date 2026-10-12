import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/exam_repositories.dart';
import '../../domain/examination.dart';
import '../../domain/marks.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams/review/:examId` — every marks sheet of an examination and its
/// state. An administrator opens a sheet, approves it, or returns it with a
/// note. Approving moves the examination's approved-sheet count in the same
/// commit; the person who submitted a sheet cannot approve it (a school
/// administrator excepted) — checked here and by the rules.
class MarksReviewPage extends ConsumerWidget {
  final String examId;
  const MarksReviewPage({super.key, required this.examId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review marks')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (schoolId: schoolId, branchId: branchId, examId: examId);
          final exam = ref.watch(examProvider(key));
          final subjects = ref.watch(examSubjectsProvider(key));
          final sheets = ref.watch(examSheetsProvider(key));
          for (final v in [exam, subjects, sheets]) {
            if (v.hasError) {
              return ErrorView(
                message: userMessageFor(v.error!),
                onRetry: () {
                  ref.invalidate(examSheetsProvider(key));
                  ref.invalidate(examProvider(key));
                },
              );
            }
          }
          final e = exam.value;
          if (!exam.hasValue || !subjects.hasValue || !sheets.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          if (e == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This examination could not be found.',
            );
          }
          return _Review(
            exam: e,
            examKey: key,
            subjects: subjects.value!,
            sheets: sheets.value!,
            actor: examActorFor(tenant),
          );
        },
      ),
    );
  }
}

class _Review extends ConsumerStatefulWidget {
  final Examination exam;
  final ExamKey examKey;
  final List<ExaminationSubject> subjects;
  final List<MarksSheet> sheets;
  final ExamActor actor;

  const _Review({
    required this.exam,
    required this.examKey,
    required this.subjects,
    required this.sheets,
    required this.actor,
  });

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(examSheetsProvider(widget.examKey));
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    final sections =
        ref
            .watch(
              sectionsProvider((
                schoolId: exam.schoolId,
                branchId: exam.branchId,
                academicYearId: exam.academicYearId,
                classId: exam.classId,
              )),
            )
            .value ??
        const [];
    final covered = exam.sectionId == null
        ? sections
        : sections.where((s) => s.sectionId == exam.sectionId).toList();
    final byId = {for (final s in widget.sheets) s.id: s};
    final repo = ref.read(marksRepositoryProvider);
    final open = exam.status == ExamStatus.inProgress;
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(exam.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ExamStatusPill(exam.status),
              Text(
                '${exam.approvedSheets} of ${exam.sheetCount} sheets approved',
              ),
            ],
          ),
          if (!open)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Marks entry is not open, so sheets cannot change.'),
            ),
          const SizedBox(height: AppSpacing.md),
          if (widget.subjects.isEmpty || covered.isEmpty)
            const EmptyView(
              icon: Icons.fact_check_outlined,
              message: 'There are no marks sheets for this examination.',
            )
          else
            for (final subject in widget.subjects)
              for (final section in covered)
                Builder(
                  builder: (context) {
                    final sheet =
                        byId[MarksSheet.idFor(
                          exam.examId,
                          subject.subjectId,
                          section.sectionId,
                        )];
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Padding(
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
                                  '${subject.subjectName} — ${section.name}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                SheetStatusPill(sheet?.status),
                                if (sheet != null)
                                  Text('${sheet.rosterCount} students'),
                                if (sheet?.submittedAt != null)
                                  Text(
                                    'submitted ${formatInstant(sheet!.submittedAt)}',
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                if (sheet != null)
                                  OutlinedButton(
                                    onPressed: () => context.push(
                                      AppRoutes.examMarks
                                          .replaceFirst(':examId', exam.examId)
                                          .replaceFirst(
                                            ':subjectId',
                                            subject.subjectId,
                                          )
                                          .replaceFirst(
                                            ':sectionId',
                                            section.sectionId,
                                          ),
                                    ),
                                    child: const Text('Open'),
                                  ),
                                if (open &&
                                    sheet?.status == SheetStatus.submitted)
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            if (!await confirmAction(
                                              context,
                                              title: 'Approve these marks?',
                                              body:
                                                  '${subject.subjectName} — '
                                                  '${section.name} will be '
                                                  'locked for results.',
                                              action: 'Approve',
                                            )) {
                                              return;
                                            }
                                            await _act(
                                              () => repo.approveSheet(
                                                exam: exam,
                                                sheet: sheet!,
                                                actor: widget.actor,
                                              ),
                                              'Approved.',
                                            );
                                          },
                                    child: const Text('Approve'),
                                  ),
                                if (open &&
                                    (sheet?.status == SheetStatus.submitted ||
                                        sheet?.status == SheetStatus.approved))
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final note = await askReason(
                                              context,
                                              title: 'Return for correction?',
                                              body:
                                                  'Tell the teacher what to '
                                                  'check.',
                                              action: 'Return',
                                            );
                                            if (note == null) return;
                                            await _act(
                                              () => repo.returnSheet(
                                                exam: exam,
                                                sheet: sheet!,
                                                note: note,
                                                actor: widget.actor,
                                              ),
                                              'Returned for correction.',
                                            );
                                          },
                                    child: const Text('Return'),
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
      ),
    );
  }
}
