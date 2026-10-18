import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../students/domain/student.dart';
import '../../domain/exam_enums.dart';
import '../../domain/exam_repositories.dart';
import '../../domain/exam_rules.dart';
import '../../domain/examination.dart';
import '../../domain/marks.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams/marks/:examId/:subjectId/:sectionId` — marks for one subject in
/// one section. A wide table on tablets and desktops, a compact card per
/// student on phones. **Zero is a score**: absent, exempted and not-yet-entered
/// are separate choices, never silently zero. Saving writes only what changed
/// and keeps every earlier value in the entry's revision history.
class MarksEntryPage extends ConsumerWidget {
  final String examId;
  final String subjectId;
  final String sectionId;

  const MarksEntryPage({
    super.key,
    required this.examId,
    required this.subjectId,
    required this.sectionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter marks')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final examKey = (
            schoolId: schoolId,
            branchId: branchId,
            examId: examId,
          );
          final exam = ref.watch(examProvider(examKey));
          final subjects = ref.watch(examSubjectsProvider(examKey));
          final roster = ref.watch(
            sectionRosterProvider((exam: examKey, sectionId: sectionId)),
          );
          final data = ref.watch(
            sheetDataProvider((
              exam: examKey,
              subjectId: subjectId,
              sectionId: sectionId,
            )),
          );
          for (final v in [exam, subjects, roster, data]) {
            if (v.hasError) {
              return ErrorView(
                message: userMessageFor(v.error!),
                onRetry: () {
                  ref.invalidate(examProvider(examKey));
                  ref.invalidate(sheetDataProvider);
                  ref.invalidate(sectionRosterProvider);
                },
              );
            }
          }
          if (!exam.hasValue ||
              !subjects.hasValue ||
              !roster.hasValue ||
              !data.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          final e = exam.value;
          final subject = subjects.value!
              .where((s) => s.subjectId == subjectId)
              .firstOrNull;
          if (e == null || subject == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This examination subject could not be found.',
            );
          }
          return _Sheet(
            key: ValueKey(
              '${e.examId}/$subjectId/$sectionId/${data.value!.sheet?.revision}',
            ),
            exam: e,
            subject: subject,
            sectionId: sectionId,
            roster: roster.value!,
            data: data.value!,
            actor: examActorFor(tenant),
            examKey: examKey,
          );
        },
      ),
    );
  }
}

class _Sheet extends ConsumerStatefulWidget {
  final Examination exam;
  final ExaminationSubject subject;
  final String sectionId;
  final List<Student> roster;
  final SheetData data;
  final ExamActor actor;
  final ExamKey examKey;

  const _Sheet({
    super.key,
    required this.exam,
    required this.subject,
    required this.sectionId,
    required this.roster,
    required this.data,
    required this.actor,
    required this.examKey,
  });

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  late Map<String, MarksEntry> _stored;
  late Map<String, MarksEntry> _work;
  final _marks = <String, TextEditingController>{};
  final _theory = <String, TextEditingController>{};
  final _practical = <String, TextEditingController>{};
  final _remark = <String, TextEditingController>{};
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _busy = false;
  String? _error;

  ExaminationSubject get subject => widget.subject;

  @override
  void initState() {
    super.initState();
    _stored = {for (final e in widget.data.entries) e.studentId: e};
    final sheetId = MarksSheet.idFor(
      widget.exam.examId,
      subject.subjectId,
      widget.sectionId,
    );
    _work = {
      for (final s in widget.roster)
        s.studentId:
            _stored[s.studentId] ??
            MarksEntry(
              sheetId: sheetId,
              examId: widget.exam.examId,
              subjectId: subject.subjectId,
              studentId: s.studentId,
              studentName: s.displayName,
              rollNumber: s.currentRollNumber,
              classId: widget.exam.classId,
              sectionId: widget.sectionId,
              academicYearId: widget.exam.academicYearId,
              schoolId: widget.exam.schoolId,
              branchId: widget.exam.branchId,
            ),
    };
    for (final e in _work.values) {
      _marks[e.studentId] = TextEditingController(text: _text(e.marks));
      _theory[e.studentId] = TextEditingController(text: _text(e.theory));
      _practical[e.studentId] = TextEditingController(text: _text(e.practical));
      _remark[e.studentId] = TextEditingController(text: e.remark);
    }
  }

  static String _text(double? v) => v == null ? '' : fmtNum(v);

  @override
  void dispose() {
    for (final m in [_marks, _theory, _practical, _remark]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _search.dispose();
    super.dispose();
  }

  bool get _editable {
    if (widget.exam.status != ExamStatus.inProgress) return false;
    final s = widget.data.sheet;
    return s == null || s.status.isEditable;
  }

  bool _changed(MarksEntry w) {
    final o = _stored[w.studentId];
    if (o == null) {
      return w.status != MarkStatus.pending || w.remark.trim().isNotEmpty;
    }
    return o.status != w.status ||
        o.remark.trim() != w.remark.trim() ||
        (w.status == MarkStatus.entered &&
            (o.effectiveMarks != w.effectiveMarks ||
                o.theory != w.theory ||
                o.practical != w.practical));
  }

  void _update(String id, MarksEntry Function(MarksEntry e) f) {
    setState(() {
      _work[id] = f(_work[id]!);
      _error = null;
    });
  }

  void _onMarks(String id, String text) {
    final v = double.tryParse(text.trim());
    _update(
      id,
      (e) => text.trim().isEmpty
          ? e.copyWith(clearMarks: true)
          : e.copyWith(marks: v ?? -1),
    );
  }

  void _onComponent(String id) {
    final t = double.tryParse(_theory[id]!.text.trim());
    final p = double.tryParse(_practical[id]!.text.trim());
    _update(
      id,
      (e) => MarksEntry(
        sheetId: e.sheetId,
        examId: e.examId,
        subjectId: e.subjectId,
        studentId: e.studentId,
        studentName: e.studentName,
        rollNumber: e.rollNumber,
        classId: e.classId,
        sectionId: e.sectionId,
        academicYearId: e.academicYearId,
        schoolId: e.schoolId,
        branchId: e.branchId,
        status: e.status,
        theory: _theory[id]!.text.trim().isEmpty ? null : (t ?? -1),
        practical: _practical[id]!.text.trim().isEmpty ? null : (p ?? -1),
        remark: e.remark,
        revision: e.revision,
        updatedBy: e.updatedBy,
        updatedAt: e.updatedAt,
      ),
    );
  }

  String? _problem(MarksEntry e) {
    if (e.status != MarkStatus.entered) return null;
    return e.validate(subject);
  }

  int get _decided =>
      _work.values.where((e) => e.status != MarkStatus.pending).length;

  Future<bool> _save() async {
    final changed = [
      for (final e in _work.values)
        if (_changed(e)) e,
    ];
    if (changed.isEmpty) return true;
    for (final e in changed) {
      final p = e.validate(subject);
      if (p != null) {
        setState(() => _error = '${e.studentName}: $p');
        return false;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(marksRepositoryProvider)
          .saveEntries(
            exam: widget.exam,
            subject: subject,
            sectionId: widget.sectionId,
            changed: changed,
            rosterCount: widget.roster.length,
            actor: widget.actor,
          );
      ref.invalidate(sheetDataProvider);
      return true;
    } catch (e) {
      if (e is PartialSaveFailure) {
        // Move the stored copy of what did save forward, so the retry sends
        // only the rest and with the right revisions (ACAD-3).
        for (final id in e.savedIds) {
          final w = _work.values.where((x) => x.id == id).firstOrNull;
          if (w == null) continue;
          final saved = w.copyWith(revision: w.revision + 1);
          _stored[w.studentId] = saved;
          _work[w.studentId] = saved;
        }
      }
      if (mounted) setState(() => _error = userMessageFor(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveClicked() async {
    final messenger = ScaffoldMessenger.of(context);
    if (await _save() && mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('Marks saved.')));
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = ExamRules.checkSubmitSheet(
      sheet: widget.data.sheet,
      subject: subject,
      roster: _work.values.toList(),
    );
    if (problem != null) return setState(() => _error = problem);
    if (!await confirmAction(
      context,
      title: 'Submit for review?',
      body:
          'You will not be able to change these marks unless the reviewer '
          'returns the sheet.',
      action: 'Submit',
    )) {
      return;
    }
    if (!await _save() || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(marksRepositoryProvider);
      final sheet = await repo.fetchSheet(
        widget.exam,
        subject.subjectId,
        widget.sectionId,
      );
      if (sheet == null) throw StateError('The sheet was not saved.');
      await repo.submitSheet(
        exam: widget.exam,
        sheet: sheet,
        actor: widget.actor,
      );
      ref.invalidate(sheetDataProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Submitted for review.')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MarksEntry> _visible() {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final s in widget.roster)
        if (_work[s.studentId] case final e?)
          if ((q.isEmpty ||
                  e.studentName.toLowerCase().contains(q) ||
                  (e.rollNumber ?? '').toLowerCase().contains(q)) &&
              (_filter == 'ALL' || e.status.wireValue == _filter))
            e,
    ];
  }

  Widget _entryControls(MarksEntry e, {required bool compact}) {
    final id = e.studentId;
    final problem = _problem(e);
    final status = DropdownButton<MarkStatus>(
      value: e.status,
      isDense: true,
      onChanged: _editable
          ? (v) => _update(id, (x) => x.copyWith(status: v))
          : null,
      items: [
        for (final s in MarkStatus.values)
          DropdownMenuItem(value: s, child: Text(s.displayName)),
      ],
    );
    final entered = e.status == MarkStatus.entered;
    Widget field(
      TextEditingController c,
      String label,
      VoidCallback onChanged,
    ) => SizedBox(
      width: 96,
      child: TextField(
        controller: c,
        enabled: _editable && entered,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          errorText: problem != null && entered ? '' : null,
        ),
      ),
    );
    final fields = subject.hasComponents
        ? [
            field(
              _theory[id]!,
              'Theory /${fmtNum(subject.theoryMax)}',
              () => _onComponent(id),
            ),
            field(
              _practical[id]!,
              'Practical /${fmtNum(subject.practicalMax)}',
              () => _onComponent(id),
            ),
          ]
        : [
            field(
              _marks[id]!,
              'Marks /${fmtNum(subject.maxMarks)}',
              () => _onMarks(id, _marks[id]!.text),
            ),
          ];
    final remark = SizedBox(
      width: compact ? double.infinity : 200,
      child: TextField(
        controller: _remark[id],
        enabled: _editable,
        onChanged: (t) => _update(id, (x) => x.copyWith(remark: t)),
        decoration: const InputDecoration(labelText: 'Remark', isDense: true),
      ),
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(label: 'Status for ${e.studentName}', child: status),
        ...fields,
        remark,
        if (problem != null && entered)
          Text(
            problem,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.data.sheet;
    final dirty = _work.values.where(_changed).length;
    final visible = _visible();
    return PageColumn(
      maxWidth: 1000,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            '${widget.exam.name} — ${subject.subjectName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Maximum ${fmtNum(subject.maxMarks)}'),
              Text(
                subject.passMarks == null
                    ? 'Pass: per grading scheme'
                    : 'Pass ${fmtNum(subject.passMarks)}',
              ),
              SheetStatusPill(sheet?.status),
              Text('$_decided of ${widget.roster.length} decided'),
            ],
          ),
          if (sheet?.status == SheetStatus.returned &&
              sheet?.reviewNote != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Returned for correction'),
                subtitle: Text(sheet!.reviewNote!),
              ),
            ),
          if (!_editable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                widget.exam.status != ExamStatus.inProgress
                    ? 'Marks entry is not open for this examination.'
                    : 'This sheet is ${sheet?.status.displayName.toLowerCase()} '
                          'and is read-only.',
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search name or roll number',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              for (final f in [
                ('ALL', 'All'),
                ('PENDING', 'Pending'),
                ('ENTERED', 'Entered'),
                ('ABSENT', 'Absent'),
                ('EXEMPTED', 'Exempted'),
              ])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.roster.isEmpty)
            const EmptyView(
              icon: Icons.groups_outlined,
              message:
                  'No active students are placed in this section, so there '
                  'is nothing to enter.',
            )
          else if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: Text('No students match.')),
            )
          else
            ResponsiveBuilder(
              builder: (context, size) {
                final compact = size.isMobile;
                return Column(
                  children: [
                    for (final e in visible)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: compact
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${e.rollNumber == null ? '' : '${e.rollNumber}. '}${e.studentName}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    _entryControls(e, compact: true),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 220,
                                      child: Text(
                                        '${e.rollNumber == null ? '' : '${e.rollNumber}. '}${e.studentName}',
                                      ),
                                    ),
                                    Expanded(
                                      child: _entryControls(e, compact: false),
                                    ),
                                    if (_changed(e))
                                      const Icon(Icons.circle, size: 10),
                                  ],
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (_editable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || dirty == 0 ? null : _saveClicked,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      dirty == 0 ? 'Save draft' : 'Save draft ($dirty)',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit for review'),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
