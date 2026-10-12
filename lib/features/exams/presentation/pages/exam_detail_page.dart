import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../domain/exam_enums.dart';
import '../../domain/exam_repositories.dart';
import '../../domain/examination.dart';
import '../../domain/marks.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams/detail/:examId` — one examination: its subjects and marks
/// configuration, the workflow actions open to the person, and the marks
/// sheets they may work on.
class ExamDetailPage extends ConsumerWidget {
  final String examId;
  const ExamDetailPage({super.key, required this.examId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Examination')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (schoolId: schoolId, branchId: branchId, examId: examId);
          final exam = ref.watch(examProvider(key));
          return exam.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(examProvider(key)),
            ),
            data: (e) => e == null
                ? const EmptyView(
                    icon: Icons.search_off,
                    message: 'This examination could not be found.',
                  )
                : _Detail(tenant: tenant, exam: e, examKey: key),
          );
        },
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final Examination exam;
  final ExamKey examKey;

  const _Detail({
    required this.tenant,
    required this.exam,
    required this.examKey,
  });

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _busy = false;

  Examination get exam => widget.exam;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ExamActor get _actor => examActorFor(widget.tenant);

  /// Sections the examination covers.
  List<Section> _sections() {
    final all =
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
        const <Section>[];
    final active = [
      for (final s in all)
        if (s.status == ActivationStatus.active) s,
    ];
    return exam.sectionId == null
        ? active
        : [
            for (final s in all)
              if (s.sectionId == exam.sectionId) s,
          ];
  }

  Future<void> _editSubject(
    List<ExaminationSubject> existing, {
    ExaminationSubject? subject,
  }) async {
    final available = await readAlive(
      ref,
      classSubjectsProvider((
        schoolId: exam.schoolId,
        branchId: exam.branchId,
        academicYearId: exam.academicYearId,
        classId: exam.classId,
      )),
    );
    if (!mounted) return;
    final taken = {for (final s in existing) s.subjectId};
    final result = await showDialog<ExaminationSubject>(
      context: context,
      builder: (_) => _SubjectDialog(
        exam: exam,
        subject: subject,
        choices: [
          for (final l in available)
            if (subject != null || !taken.contains(l.subjectId))
              (id: l.subjectId, name: l.subjectName),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => ref
          .read(examRepositoryProvider)
          .saveSubject(exam, result, isNew: subject == null, actor: _actor),
      'Subject saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;
    final repo = ref.read(examRepositoryProvider);
    final canManage = t.can(Permission.manageExams);
    final canApprove = t.can(Permission.approveResults);
    final canEnter = t.can(Permission.enterMarks);
    final subjects =
        ref.watch(examSubjectsProvider(widget.examKey)).value ??
        const <ExaminationSubject>[];
    final sections = _sections();
    final expectedSheets = subjects.length * sections.length;

    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExamStatusPill(exam.status),
              Text(exam.type.displayName),
              if (exam.resultVersion > 0)
                StatusPill(label: 'Result version ${exam.resultVersion}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${exam.classLabel ?? exam.classId}'
                  '${exam.sectionId == null ? ' (all sections)' : ''}',
                ),
                Text(
                  '${formatDateKey(exam.startDateKey)} – '
                  '${formatDateKey(exam.endDateKey)}',
                ),
                if (exam.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(exam.description),
                ],
                if (exam.instructions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    exam.instructions,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'Subjects and marks',
            actions: [
              if (canManage && exam.status.isConfigurable)
                TextButton.icon(
                  onPressed: _busy ? null : () => _editSubject(subjects),
                  icon: const Icon(Icons.add),
                  label: const Text('Add subject'),
                ),
            ],
            child: subjects.isEmpty
                ? const Text('No subjects configured yet.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Subject')),
                        DataColumn(label: Text('Max'), numeric: true),
                        DataColumn(label: Text('Pass'), numeric: true),
                        DataColumn(label: Text('Weight'), numeric: true),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final s in subjects)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  s.hasComponents
                                      ? '${s.subjectName} (T${fmtNum(s.theoryMax)}+P${fmtNum(s.practicalMax)})'
                                      : s.subjectName,
                                ),
                              ),
                              DataCell(Text(fmtNum(s.maxMarks))),
                              DataCell(
                                Text(
                                  s.passMarks == null
                                      ? 'scheme'
                                      : fmtNum(s.passMarks),
                                ),
                              ),
                              DataCell(Text(fmtNum(s.weightage))),
                              DataCell(
                                Text(
                                  s.dateKey == null
                                      ? '–'
                                      : formatDateKey(s.dateKey!),
                                ),
                              ),
                              DataCell(
                                canManage && exam.status.isConfigurable
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Edit ${s.subjectName}',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _editSubject(
                                                    subjects,
                                                    subject: s,
                                                  ),
                                          ),
                                          IconButton(
                                            tooltip: 'Remove ${s.subjectName}',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () async {
                                                    if (!await confirmAction(
                                                      context,
                                                      title: 'Remove subject?',
                                                      body: s.subjectName,
                                                      action: 'Remove',
                                                    )) {
                                                      return;
                                                    }
                                                    await _run(
                                                      () => repo.removeSubject(
                                                        exam,
                                                        s,
                                                        actor: _actor,
                                                      ),
                                                      'Subject removed.',
                                                    );
                                                  },
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          if (canManage || canApprove)
            SectionCard(
              title: 'Actions',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (canManage && exam.status.isConfigurable)
                    OutlinedButton.icon(
                      onPressed: () => context.go(
                        AppRoutes.examEdit.replaceFirst(':examId', exam.examId),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit details'),
                    ),
                  if (canManage && exam.status == ExamStatus.draft)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => repo.schedule(exam, actor: _actor),
                              'Examination scheduled.',
                            ),
                      icon: const Icon(Icons.event_available),
                      label: const Text('Schedule'),
                    ),
                  if (canManage && exam.status == ExamStatus.scheduled)
                    FilledButton.icon(
                      onPressed: _busy || expectedSheets == 0
                          ? null
                          : () async {
                              if (!await confirmAction(
                                context,
                                title: 'Open marks entry?',
                                body:
                                    'Subjects and marks can no longer be '
                                    'changed. $expectedSheets marks sheet(s) '
                                    '(${subjects.length} subject(s) × '
                                    '${sections.length} section(s)) will '
                                    'need approval before results can be '
                                    'finalised.',
                                action: 'Open marks entry',
                              )) {
                                return;
                              }
                              await _run(
                                () => repo.startMarksEntry(
                                  exam,
                                  sheetCount: expectedSheets,
                                  actor: _actor,
                                ),
                                'Marks entry is open.',
                              );
                            },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Open marks entry'),
                    ),
                  if (canApprove &&
                      (exam.status == ExamStatus.inProgress ||
                          exam.status == ExamStatus.completed))
                    OutlinedButton.icon(
                      onPressed: () => context.go(
                        AppRoutes.examReview.replaceFirst(
                          ':examId',
                          exam.examId,
                        ),
                      ),
                      icon: const Icon(Icons.rate_review_outlined),
                      label: Text(
                        'Review marks (${exam.approvedSheets}/${exam.sheetCount})',
                      ),
                    ),
                  if (canApprove &&
                      (exam.status == ExamStatus.inProgress ||
                          exam.status == ExamStatus.completed ||
                          exam.status == ExamStatus.published ||
                          exam.status == ExamStatus.withdrawn))
                    FilledButton.icon(
                      onPressed: () => context.go(
                        AppRoutes.examResults.replaceFirst(
                          ':examId',
                          exam.examId,
                        ),
                      ),
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Results'),
                    ),
                  if (canManage && exam.status == ExamStatus.published)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final reason = await askReason(
                                context,
                                title: 'Withdraw this result?',
                                body:
                                    'Families stop seeing it at once. It '
                                    'stays on record and can be corrected '
                                    'and published again as a new version.',
                                action: 'Withdraw',
                              );
                              if (reason == null) return;
                              await _run(
                                () => repo.withdraw(
                                  exam,
                                  reason: reason,
                                  actor: _actor,
                                ),
                                'Result withdrawn.',
                              );
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Withdraw'),
                    ),
                  if (canManage &&
                      (exam.status == ExamStatus.withdrawn ||
                          exam.status == ExamStatus.completed))
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final reason = await askReason(
                                context,
                                title: 'Reopen for correction?',
                                body:
                                    'Marks entry reopens. Earlier results '
                                    'stay on record; finalising again '
                                    'creates a new version.',
                                action: 'Reopen',
                              );
                              if (reason == null) return;
                              await _run(
                                () => repo.reopen(
                                  exam,
                                  reason: reason,
                                  actor: _actor,
                                ),
                                'Marks entry reopened.',
                              );
                            },
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Reopen for correction'),
                    ),
                  if (canManage &&
                      (exam.status == ExamStatus.draft ||
                          exam.status == ExamStatus.scheduled ||
                          exam.status == ExamStatus.inProgress))
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final reason = await askReason(
                                context,
                                title: 'Cancel this examination?',
                                body: 'It is kept on record as cancelled.',
                                action: 'Cancel examination',
                              );
                              if (reason == null) return;
                              await _run(
                                () => repo.cancel(
                                  exam,
                                  reason: reason,
                                  actor: _actor,
                                ),
                                'Examination cancelled.',
                              );
                            },
                      icon: const Icon(Icons.block),
                      label: const Text('Cancel'),
                    ),
                  if (canApprove)
                    TextButton.icon(
                      onPressed: () => context.go(
                        AppRoutes.examHistory.replaceFirst(
                          ':examId',
                          exam.examId,
                        ),
                      ),
                      icon: const Icon(Icons.history),
                      label: const Text('History'),
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
            ),
          if (canEnter && exam.status == ExamStatus.inProgress)
            _SheetList(
              tenant: t,
              exam: exam,
              examKey: widget.examKey,
              subjects: subjects,
              sections: sections,
            ),
        ],
      ),
    );
  }
}

/// The (subject × section) sheets the person may work on, with their state.
class _SheetList extends ConsumerWidget {
  final TenantContext tenant;
  final Examination exam;
  final ExamKey examKey;
  final List<ExaminationSubject> subjects;
  final List<Section> sections;

  const _SheetList({
    required this.tenant,
    required this.exam,
    required this.examKey,
    required this.subjects,
    required this.sections,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        tenant.role == UserRole.schoolAdmin ||
        tenant.role == UserRole.branchAdmin ||
        tenant.role == UserRole.platformAdmin;
    Set<String>? mine;
    if (!isAdmin) {
      final staff = ref
          .watch(
            ownStaffProvider((
              schoolId: exam.schoolId,
              branchId: exam.branchId,
              userId: tenant.user.userId,
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
      mine = {
        for (final f in facts ?? const [])
          if (staff != null &&
              f.teacherStaffId == staff.staffId &&
              f.subjectId != null &&
              f.classId == exam.classId)
            '${f.subjectId}/${f.sectionId}',
      };
    }
    final rows = [
      for (final s in subjects)
        for (final sec in sections)
          if (isAdmin ||
              (mine?.contains('${s.subjectId}/${sec.sectionId}') ?? false))
            (subject: s, section: sec),
    ];
    return SectionCard(
      title: isAdmin ? 'Marks sheets' : 'Your marks sheets',
      child: rows.isEmpty
          ? const Text(
              'You have no subject assigned in this class, so there are no '
              'marks for you to enter.',
            )
          : Column(
              children: [
                for (final r in rows)
                  _SheetTile(
                    exam: exam,
                    subject: r.subject,
                    section: r.section,
                  ),
              ],
            ),
    );
  }
}

final _sheetProvider = FutureProvider.autoDispose
    .family<MarksSheet?, (Examination, String, String)>((ref, k) {
      return ref.read(marksRepositoryProvider).fetchSheet(k.$1, k.$2, k.$3);
    });

class _SheetTile extends ConsumerWidget {
  final Examination exam;
  final ExaminationSubject subject;
  final Section section;

  const _SheetTile({
    required this.exam,
    required this.subject,
    required this.section,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(
      _sheetProvider((exam, subject.subjectId, section.sectionId)),
    );
    final status = sheet.value?.status;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${subject.subjectName} — ${section.name}'),
      subtitle: Wrap(
        spacing: AppSpacing.sm,
        children: [
          SheetStatusPill(status),
          if (sheet.value?.reviewNote != null && status == SheetStatus.returned)
            Text('“${sheet.value!.reviewNote}”'),
        ],
      ),
      trailing: FilledButton.tonal(
        onPressed: () async {
          await context.push(
            AppRoutes.examMarks
                .replaceFirst(':examId', exam.examId)
                .replaceFirst(':subjectId', subject.subjectId)
                .replaceFirst(':sectionId', section.sectionId),
          );
          ref.invalidate(_sheetProvider);
        },
        child: Text(
          status == null || status.isEditable ? 'Enter marks' : 'View',
        ),
      ),
    );
  }
}

class _SubjectDialog extends StatefulWidget {
  final Examination exam;
  final ExaminationSubject? subject;
  final List<({String id, String name})> choices;

  const _SubjectDialog({
    required this.exam,
    required this.subject,
    required this.choices,
  });

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  late final TextEditingController _max;
  late final TextEditingController _pass;
  late final TextEditingController _weight;
  late final TextEditingController _theory;
  late final TextEditingController _practical;
  String? _subjectId;
  String? _dateKey;
  TimeOfDay? _from;
  TimeOfDay? _to;
  bool _components = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _max = TextEditingController(text: s == null ? '100' : fmtNum(s.maxMarks));
    _pass = TextEditingController(
      text: s?.passMarks == null ? '' : fmtNum(s!.passMarks),
    );
    _weight = TextEditingController(
      text: s == null ? '1' : fmtNum(s.weightage),
    );
    _components = s?.hasComponents ?? false;
    _theory = TextEditingController(
      text: s?.theoryMax == null ? '' : fmtNum(s!.theoryMax),
    );
    _practical = TextEditingController(
      text: s?.practicalMax == null ? '' : fmtNum(s!.practicalMax),
    );
    _subjectId = s?.subjectId;
    _dateKey = s?.dateKey;
    if (s?.startMin != null) {
      _from = TimeOfDay(hour: s!.startMin! ~/ 60, minute: s.startMin! % 60);
      _to = TimeOfDay(hour: s.endMin! ~/ 60, minute: s.endMin! % 60);
    }
  }

  @override
  void dispose() {
    _max.dispose();
    _pass.dispose();
    _weight.dispose();
    _theory.dispose();
    _practical.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _subjectId;
    if (id == null) return setState(() => _error = 'Choose a subject.');
    final name =
        widget.subject?.subjectName ??
        widget.choices.firstWhere((c) => c.id == id).name;
    final s = ExaminationSubject(
      examId: widget.exam.examId,
      subjectId: id,
      schoolId: widget.exam.schoolId,
      branchId: widget.exam.branchId,
      academicYearId: widget.exam.academicYearId,
      classId: widget.exam.classId,
      subjectName: name,
      maxMarks: double.tryParse(_max.text.trim()) ?? 0,
      passMarks: _pass.text.trim().isEmpty
          ? null
          : double.tryParse(_pass.text.trim()) ?? -1,
      weightage: double.tryParse(_weight.text.trim()) ?? 0,
      dateKey: _dateKey,
      startMin: _from == null || _to == null
          ? null
          : _from!.hour * 60 + _from!.minute,
      endMin: _from == null || _to == null
          ? null
          : _to!.hour * 60 + _to!.minute,
      theoryMax: _components ? double.tryParse(_theory.text.trim()) : null,
      practicalMax: _components
          ? double.tryParse(_practical.text.trim())
          : null,
      revision: widget.subject?.revision ?? 1,
    );
    final problem = s.validate(
      examStartKey: widget.exam.startDateKey,
      examEndKey: widget.exam.endDateKey,
    );
    if (problem != null) return setState(() => _error = problem);
    Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.subject == null ? 'Add subject' : 'Edit subject'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.subject == null)
                DropdownButtonFormField<String>(
                  value: _subjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: [
                    for (final c in widget.choices)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _subjectId = v),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.subject!.subjectName),
                ),
              TextField(
                controller: _max,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Maximum marks'),
              ),
              TextField(
                controller: _pass,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Passing marks (blank = scheme percentage)',
                ),
              ),
              TextField(
                controller: _weight,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weightage'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Theory and practical components'),
                value: _components,
                onChanged: (v) => setState(() => _components = v),
              ),
              if (_components) ...[
                TextField(
                  controller: _theory,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Theory maximum',
                  ),
                ),
                TextField(
                  controller: _practical,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Practical maximum',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final start = AttendanceDate.parse(
                        widget.exam.startDateKey,
                      );
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dateKey == null
                            ? start
                            : AttendanceDate.parse(_dateKey!),
                        firstDate: start,
                        lastDate: AttendanceDate.parse(widget.exam.endDateKey),
                      );
                      if (d != null) {
                        setState(() => _dateKey = AttendanceDate.key(d));
                      }
                    },
                    child: Text(
                      _dateKey == null ? 'Exam date' : formatDateKey(_dateKey!),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime:
                            _from ?? const TimeOfDay(hour: 9, minute: 0),
                        helpText: 'Starts',
                      );
                      if (t == null || !context.mounted) return;
                      final e = await showTimePicker(
                        context: context,
                        initialTime: t.replacing(hour: (t.hour + 2) % 24),
                        helpText: 'Ends',
                      );
                      if (e != null) {
                        setState(() {
                          _from = t;
                          _to = e;
                        });
                      }
                    },
                    child: Text(
                      _from == null
                          ? 'Time (optional)'
                          : '${_from!.format(context)} – ${_to!.format(context)}',
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
