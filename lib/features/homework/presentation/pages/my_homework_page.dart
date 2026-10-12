import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../announcements/presentation/widgets/current_announcements_card.dart';
import '../../../students/domain/student.dart';
import '../../../students/domain/student_status.dart';
import '../../domain/homework.dart';
import '../../domain/homework_rules.dart';
import '../../domain/homework_submission.dart';
import '../providers/homework_providers.dart';
import '../widgets/family_scope.dart';
import '../widgets/homework_widgets.dart';

/// `/my-homework` — a parent's view of a linked child's homework: what is
/// due, overdue, handed in, sent back, and graded. Only the child's own
/// section's published homework is listed; the child's submissions are read
/// through the parent link.
class MyHomeworkPage extends StatelessWidget {
  const MyHomeworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('My homework')),
      body: FamilyScope(
        builder: (context, tenant, children, child) => _ChildHomework(
          child: child,
          children: children,
          userId: tenant.user.userId,
        ),
      ),
    );
  }
}

class _ChildHomework extends ConsumerStatefulWidget {
  final Student child;
  final List<Student> children;
  final String userId;

  const _ChildHomework({
    required this.child,
    required this.children,
    required this.userId,
  });

  @override
  ConsumerState<_ChildHomework> createState() => _ChildHomeworkState();
}

class _ChildHomeworkState extends ConsumerState<_ChildHomework> {
  FamilyHomeworkState? _state;
  String? _subjectId;

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    final year = c.currentAcademicYearId;
    final classId = c.currentClassId;
    final sectionId = c.currentSectionId;
    if (c.status != StudentStatus.active) {
      return const EmptyView(
        icon: Icons.info_outline,
        message:
            'This child is not currently enrolled, so there is no active '
            'homework. Past work stays on record with the school.',
      );
    }
    if (year == null || classId == null || sectionId == null) {
      return const EmptyView(
        icon: Icons.class_outlined,
        message:
            'This child has not been placed in a class and section yet, so '
            'there is no homework to show.',
      );
    }
    final hwKey = (
      schoolId: c.schoolId,
      branchId: c.branchId,
      academicYearId: year,
      classId: classId,
      sectionId: sectionId,
    );
    final subKey = (
      schoolId: c.schoolId,
      branchId: c.branchId,
      studentId: c.studentId,
      academicYearId: year,
    );
    final hw = ref.watch(sectionHomeworkProvider(hwKey));
    final subs = ref.watch(childSubmissionsProvider(subKey));
    final updates = ref.watch(
      homeworkUpdatesProvider((
        schoolId: c.schoolId,
        branchId: c.branchId,
        userId: widget.userId,
      )),
    );

    if (hw.isLoading || subs.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hw.hasError || subs.hasError) {
      return ErrorView(
        message: userMessageFor((hw.error ?? subs.error)!),
        onRetry: () {
          ref.invalidate(sectionHomeworkProvider(hwKey));
          ref.invalidate(childSubmissionsProvider(subKey));
        },
      );
    }
    final byHomework = {
      for (final s in subs.value ?? const <HomeworkSubmission>[])
        s.homeworkId: s,
    };
    final now = DateTime.now();
    final rows = [
      for (final h in hw.value ?? const <Homework>[])
        (
          homework: h,
          submission: byHomework[h.homeworkId],
          state: HomeworkRules.familyState(
            homework: h,
            submission: byHomework[h.homeworkId],
            now: now,
          ),
        ),
    ];
    int count(FamilyHomeworkState s) => rows.where((r) => r.state == s).length;
    final subjects = {
      for (final r in rows) r.homework.subjectId: r.homework.subjectName,
    };
    final shown = [
      for (final r in rows)
        if ((_state == null || r.state == _state) &&
            (_subjectId == null || r.homework.subjectId == _subjectId))
          r,
    ];
    // Things still to do come first, soonest deadline first.
    shown.sort((a, b) {
      int rank(FamilyHomeworkState s) => switch (s) {
        FamilyHomeworkState.overdue => 0,
        FamilyHomeworkState.revision => 1,
        FamilyHomeworkState.upcoming => 2,
        _ => 3,
      };
      final r = rank(a.state).compareTo(rank(b.state));
      return r != 0 ? r : a.homework.dueAt.compareTo(b.homework.dueAt);
    });

    return PageColumn(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sectionHomeworkProvider(hwKey));
          ref.invalidate(childSubmissionsProvider(subKey));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                CountTile(
                  label: 'To do',
                  icon: Icons.pending_actions,
                  value: count(FamilyHomeworkState.upcoming),
                  onTap: () =>
                      setState(() => _state = FamilyHomeworkState.upcoming),
                ),
                CountTile(
                  label: 'Overdue',
                  icon: Icons.warning_amber,
                  value: count(FamilyHomeworkState.overdue),
                  onTap: () =>
                      setState(() => _state = FamilyHomeworkState.overdue),
                ),
                CountTile(
                  label: 'Needs revision',
                  icon: Icons.undo,
                  value: count(FamilyHomeworkState.revision),
                  onTap: () =>
                      setState(() => _state = FamilyHomeworkState.revision),
                ),
                CountTile(
                  label: 'Submitted',
                  icon: Icons.check,
                  value: count(FamilyHomeworkState.submitted),
                  onTap: () =>
                      setState(() => _state = FamilyHomeworkState.submitted),
                ),
                CountTile(
                  label: 'Graded',
                  icon: Icons.grade_outlined,
                  value: count(FamilyHomeworkState.graded),
                  onTap: () =>
                      setState(() => _state = FamilyHomeworkState.graded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if ((updates.value ?? const []).isNotEmpty)
              SectionCard(
                title: 'Updates',
                child: Column(
                  children: [
                    for (final n in updates.value!.take(3))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          n.type == 'HOMEWORK_RETURNED'
                              ? Icons.undo
                              : Icons.grade_outlined,
                        ),
                        title: Text(n.title),
                        subtitle: Text(n.body ?? ''),
                      ),
                  ],
                ),
              ),
            CurrentAnnouncementsCard(children: widget.children, limit: 3),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<FamilyHomeworkState?>(
                    value: _state,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Show',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      for (final s in FamilyHomeworkState.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) => setState(() => _state = v),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All subjects'),
                      ),
                      for (final e in subjects.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _subjectId = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.menu_book_outlined,
                  message: 'No homework to show.',
                ),
              )
            else
              for (final r in shown)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    title: Text(
                      r.homework.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(r.homework.subjectName),
                          Text(dueLabel(r.homework)),
                          FamilyStatePill(r.state),
                          if (r.submission?.marks != null &&
                              r.homework.maxMarks != null)
                            Text(
                              '${r.submission!.marks}/${r.homework.maxMarks}',
                            ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      AppRoutes.myHomeworkDetail
                          .replaceFirst(':homeworkId', r.homework.homeworkId)
                          .replaceFirst(':studentId', widget.child.studentId),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
