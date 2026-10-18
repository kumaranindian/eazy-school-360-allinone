import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/utils/bounded_parallel.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../attendance/domain/attendance_tally.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../domain/exam_enums.dart';
import '../../domain/exam_repositories.dart';
import '../../domain/attendance_gap.dart';
import '../../domain/exam_rules.dart';
import '../../domain/examination.dart';
import '../../domain/result_calculator.dart';
import '../../domain/result_summary.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams/results/:examId` — the calculation preview, finalisation and
/// publication of an examination.
///
/// * While marks are being entered the table is **provisional**: it is
///   computed from the stored marks on every open and nothing is saved.
/// * Finalising stores the result as an immutable, versioned document with
///   the grading scheme it used and an attendance snapshot.
/// * Publishing makes that version visible to the linked parents and
///   notifies them, once.
class ExamResultsPage extends ConsumerWidget {
  final String examId;
  const ExamResultsPage({super.key, required this.examId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (schoolId: schoolId, branchId: branchId, examId: examId);
          final prov = ref.watch(provisionalResultsProvider(key));
          return prov.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(provisionalResultsProvider(key)),
            ),
            data: (p) => _Results(tenant: tenant, examKey: key, data: p),
          );
        },
      ),
    );
  }
}

class _Results extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final ExamKey examKey;
  final ProvisionalResults data;

  const _Results({
    required this.tenant,
    required this.examKey,
    required this.data,
  });

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  bool _busy = false;
  String? _progress;
  String? _error;

  Examination get exam => widget.data.exam;
  ExamActor get _actor => examActorFor(widget.tenant);

  Future<({Map<String, AttendanceSnapshot?> snapshots, int failed})>
  _attendance(List<StudentResult> results) async {
    final repo = ref.read(studentAttendanceRepositoryProvider);
    final years = ref
        .read(
          academicYearsProvider((
            schoolId: exam.schoolId,
            branchId: exam.branchId,
          )),
        )
        .value;
    final year = years
        ?.where((y) => y.academicYearId == exam.academicYearId)
        .firstOrNull;
    final from = year == null
        ? exam.startDateKey
        : AttendanceDate.key(year.startDate.toUtc());
    final to = AttendanceDate.key(SchoolTime.wallNow());
    final out = <String, AttendanceSnapshot?>{};
    var failed = 0;
    var done = 0;
    // A student's whole-year attendance (across sections, so a student who
    // moved section keeps it) is one query each; they are independent, so a
    // few run at a time instead of one after the other (PERF-1).
    await forEachBounded(results, 8, (r) async {
      try {
        final range = await repo.fetchStudentRange(
          schoolId: exam.schoolId,
          branchId: exam.branchId,
          studentId: r.studentId,
          fromKey: from,
          toKey: to,
        );
        final tally = AttendanceTally.of([
          for (final a in range.items) a.status,
        ]);
        out[r.studentId] = AttendanceSnapshot.fromTally(
          tally,
          fromKey: from,
          toKey: to,
        );
      } catch (_) {
        // Attendance is optional on a report card; absence of a snapshot is
        // printed as nothing rather than as 0%. A failed read is counted so
        // the user can decide before the results are frozen (UI-2).
        out[r.studentId] = null;
        failed++;
      }
      done++;
      if (mounted) {
        setState(
          () => _progress = 'Collecting attendance $done/${results.length}',
        );
      }
    });
    return (snapshots: out, failed: failed);
  }

  String _classLabel(String sectionId) {
    final classes = ref
        .read(
          classesProvider((
            schoolId: exam.schoolId,
            branchId: exam.branchId,
            academicYearId: exam.academicYearId,
          )),
        )
        .value;
    final sections = ref
        .read(
          sectionsProvider((
            schoolId: exam.schoolId,
            branchId: exam.branchId,
            academicYearId: exam.academicYearId,
            classId: exam.classId,
          )),
        )
        .value;
    final c = classes
        ?.where((x) => x.classId == exam.classId)
        .firstOrNull
        ?.name;
    final s = sections
        ?.where((x) => x.sectionId == sectionId)
        .firstOrNull
        ?.name;
    return [c ?? exam.classLabel ?? exam.classId, ?s].join(' – ');
  }

  Future<void> _finalize() async {
    final problem = ExamRules.checkFinalize(exam);
    if (problem != null) return setState(() => _error = problem);
    if (widget.data.incomplete > 0) {
      return setState(
        () => _error =
            '${widget.data.incomplete} student(s) still have missing marks.',
      );
    }
    if (!await confirmAction(
      context,
      title: 'Finalise these results?',
      body:
          'The results of ${widget.data.results.length} students are '
          'calculated and stored with the grading scheme '
          '"${widget.data.scheme.name}" and an attendance snapshot. They '
          'cannot be changed afterwards except by reopening the examination '
          'with a reason, which creates a new version.',
      action: 'Finalise',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remarks = await ref
          .read(resultRepositoryProvider)
          .fetchRemarks(exam);
      final collected = await _attendance(widget.data.results);
      final gap = AttendanceGap.warning(
        failed: collected.failed,
        total: widget.data.results.length,
      );
      if (gap != null &&
          !(mounted &&
              await confirmAction(
                context,
                title: 'Attendance is incomplete',
                body: gap,
                action: 'Continue without it',
              ))) {
        return;
      }
      final attendance = collected.snapshots;
      if (mounted) setState(() => _progress = 'Writing results…');
      final version = await ref
          .read(resultRepositoryProvider)
          .finalize(
            exam: exam,
            scheme: widget.data.scheme,
            results: widget.data.results,
            attendance: attendance,
            remarks: remarks,
            classLabels: {
              for (final r in widget.data.results)
                r.sectionId: _classLabel(r.sectionId),
            },
            actor: _actor,
          );
      ref.invalidate(provisionalResultsProvider(widget.examKey));
      ref.invalidate(storedResultsProvider(widget.examKey));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Results finalised (version $version).')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
      ref.invalidate(provisionalResultsProvider(widget.examKey));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _completeWriting() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remarks = await ref
          .read(resultRepositoryProvider)
          .fetchRemarks(exam);
      final collected = await _attendance(widget.data.results);
      final gap = AttendanceGap.warning(
        failed: collected.failed,
        total: widget.data.results.length,
      );
      if (gap != null &&
          !(mounted &&
              await confirmAction(
                context,
                title: 'Attendance is incomplete',
                body: gap,
                action: 'Continue without it',
              ))) {
        return;
      }
      final attendance = collected.snapshots;
      await ref
          .read(resultRepositoryProvider)
          .completeResults(
            exam: exam,
            scheme: widget.data.scheme,
            results: widget.data.results,
            attendance: attendance,
            remarks: remarks,
            classLabel: _classLabel(
              widget.data.results.firstOrNull?.sectionId ?? '',
            ),
            actor: _actor,
          );
      ref.invalidate(examProvider(widget.examKey));
      ref.invalidate(storedResultsProvider(widget.examKey));
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _publish() async {
    final problem = ExamRules.checkPublish(exam);
    if (problem != null) return setState(() => _error = problem);
    if (!await confirmAction(
      context,
      title: 'Publish these results?',
      body:
          'Parents of the class can see their child\'s result and report '
          'card, and they are notified. You can withdraw it later with a '
          'reason.',
      action: 'Publish',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(resultRepositoryProvider).publish(exam, actor: _actor);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Results published.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRemark(StudentResult r) async {
    final isAdmin =
        widget.tenant.role == UserRole.schoolAdmin ||
        widget.tenant.role == UserRole.branchAdmin ||
        widget.tenant.role == UserRole.platformAdmin;
    final current = ref
        .read(examRemarksProvider(widget.examKey))
        .value?[r.studentId];
    final teacher = TextEditingController(text: current?.teacherRemark ?? '');
    final principal = TextEditingController(
      text: current?.principalRemark ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remarks — ${r.studentName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: teacher,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Class teacher'),
            ),
            TextField(
              controller: principal,
              enabled: isAdmin,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Principal'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(resultRepositoryProvider)
          .saveRemark(
            exam: exam,
            remark: ExamRemark(
              studentId: r.studentId,
              teacherRemark: teacher.text,
              principalRemark: isAdmin
                  ? principal.text
                  : (current?.principalRemark ?? ''),
            ),
            sectionId: r.sectionId,
            actor: _actor,
            principal: isAdmin,
          );
      ref.invalidate(examRemarksProvider(widget.examKey));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final results = d.results;
    final stats = ExamStats.of(results);
    final finalized =
        exam.status == ExamStatus.completed ||
        exam.status == ExamStatus.published ||
        exam.status == ExamStatus.withdrawn;
    final provisional =
        exam.status == ExamStatus.inProgress ||
        exam.status == ExamStatus.scheduled;
    final writing =
        exam.status == ExamStatus.completed &&
        exam.resultsWritten < exam.resultCount;
    return PageColumn(
      maxWidth: 1000,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(exam.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExamStatusPill(exam.status),
              StatusPill(
                label: provisional
                    ? 'Provisional'
                    : 'Finalised v${exam.resultVersion}',
                icon: provisional ? Icons.pending_outlined : Icons.lock_outline,
                color: provisional
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
              ),
              Text('Scheme: ${d.scheme.name}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          StatChipsBar(
            chips: [
              StatChip(label: 'Students', count: stats.students),
              StatChip(label: 'Passed', count: stats.passed),
              StatChip(label: 'Failed', count: stats.failed),
              StatChip(label: 'Incomplete', count: d.incomplete),
              StatChip(
                label: 'Average',
                count: null,
                valueText: stats.averagePercentage == null
                    ? '–'
                    : '${fmtNum(stats.averagePercentage)}%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (exam.status == ExamStatus.inProgress)
                FilledButton.icon(
                  onPressed: _busy ? null : _finalize,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Finalise results'),
                ),
              if (writing)
                FilledButton.icon(
                  onPressed: _busy ? null : _completeWriting,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    'Finish writing results (${exam.resultsWritten}/${exam.resultCount})',
                  ),
                ),
              if (exam.status == ExamStatus.completed && !writing)
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.public),
                  label: const Text('Publish results'),
                ),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_progress != null) Text(_progress!),
            ],
          ),
          if (exam.status == ExamStatus.inProgress && d.incomplete > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Results cannot be finalised until every student has marks, '
                'an absence or an exemption in every subject, and every '
                'sheet is approved (${exam.approvedSheets}/${exam.sheetCount}).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (results.isEmpty)
            const EmptyView(
              icon: Icons.groups_outlined,
              message: 'No active students are enrolled for this examination.',
            )
          else
            for (final r in results)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  title: Text(
                    '${r.rollNumber == null ? '' : '${r.rollNumber}. '}${r.studentName}',
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (r.isComplete) ...[
                          Text(
                            r.totalMax == 0
                                ? '–'
                                : '${fmtNum(r.totalObtained)}/${fmtNum(r.totalMax)}',
                          ),
                          Text(
                            r.overallPercentage == null
                                ? '–'
                                : '${fmtNum(r.overallPercentage)}%',
                          ),
                          if (r.overallGrade != null)
                            Text('Grade ${r.overallGrade}'),
                          OverallPill(r.result),
                          if (r.rank != null) Text('Rank ${r.rank}'),
                          if (r.hasAbsence)
                            const StatusPill(label: 'Absent in a subject'),
                        ] else
                          StatusPill(
                            label:
                                'Missing: ${r.incompleteSubjectIds.length} subject(s)',
                            icon: Icons.warning_amber,
                            color: Theme.of(context).colorScheme.error,
                          ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (exam.status == ExamStatus.inProgress)
                        IconButton(
                          tooltip: 'Remarks for ${r.studentName}',
                          icon: const Icon(Icons.rate_review_outlined),
                          onPressed: () => _editRemark(r),
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => context.go(
                    AppRoutes.examStudentResult
                        .replaceFirst(':examId', exam.examId)
                        .replaceFirst(':studentId', r.studentId),
                  ),
                ),
              ),
          if (finalized)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                'Stored results are version ${exam.resultVersion}. '
                'Showing the marks as they are now; the report card of a '
                'finalised student always uses the stored version.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
