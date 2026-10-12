import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/examination.dart';
import '../providers/exam_providers.dart';

/// `/exams/new` and `/exams/edit/:examId` — the examination's own details.
/// Subjects and marks are configured on its detail page. The id is built from
/// academic year + class + section + name, so the same examination cannot be
/// created twice in one scope. Class, section and name are fixed afterwards.
class ExamFormPage extends StatelessWidget {
  final String? examId;
  const ExamFormPage({super.key, this.examId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(examId == null ? 'New examination' : 'Edit examination'),
      ),
      body: TimetableScope(
        showYearSelector: examId == null,
        builder: (context, tt) => _Form(tt: tt, examId: examId),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final String? examId;

  const _Form({required this.tt, required this.examId});

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _instructions = TextEditingController();
  ExamType _type = ExamType.unitTest;
  String? _classId;
  String? _sectionId; // null = all sections
  String? _schemeId;
  DateTime? _start;
  DateTime? _end;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.examId != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _load(Examination e) {
    _loaded = true;
    _name.text = e.name;
    _description.text = e.description;
    _instructions.text = e.instructions;
    _type = e.type;
    _classId = e.classId;
    _sectionId = e.sectionId;
    _schemeId = e.schemeId;
    _start = AttendanceDate.parse(e.startDateKey);
    _end = AttendanceDate.parse(e.endDateKey);
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final initial = (start ? _start : _end) ?? _start ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: start ? 'First day' : 'Last day',
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
          if (_end != null && _end!.isBefore(picked)) _end = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _save(Examination? existing, String classLabel) async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_classId == null) return setState(() => _error = 'Choose the class.');
    if (_start == null || _end == null) {
      return setState(() => _error = 'Choose the start and end dates.');
    }
    final tt = widget.tt;
    final startKey = AttendanceDate.key(_start!);
    final endKey = AttendanceDate.key(_end!);
    final name = _name.text.trim();
    final exam = existing != null
        ? existing.copyWith(
            name: name,
            description: _description.text.trim(),
            type: _type,
            schemeId: _schemeId,
            startDateKey: startKey,
            endDateKey: endKey,
            instructions: _instructions.text.trim(),
          )
        : Examination(
            examId: Examination.idFor(
              academicYearId: tt.year.academicYearId,
              classId: _classId!,
              sectionId: _sectionId,
              name: name,
            ),
            schoolId: tt.schoolId,
            branchId: tt.branchId,
            academicYearId: tt.year.academicYearId,
            classId: _classId!,
            sectionId: _sectionId,
            classLabel: classLabel,
            name: name,
            description: _description.text.trim(),
            type: _type,
            schemeId: _schemeId ?? '',
            startDateKey: startKey,
            endDateKey: endKey,
            instructions: _instructions.text.trim(),
          );
    final problem = exam.validate();
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(examRepositoryProvider);
    final actor = examActorFor(tt.tenant);
    try {
      if (existing == null) {
        await repo.create(exam, actor: actor);
      } else {
        await repo.update(exam, actor: actor);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Examination created.' : 'Examination updated.',
          ),
        ),
      );
      context.go(AppRoutes.examDetail.replaceFirst(':examId', exam.examId));
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    if (_editing) {
      final exam = ref.watch(
        examProvider((
          schoolId: tt.schoolId,
          branchId: tt.branchId,
          examId: widget.examId!,
        )),
      );
      return exam.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: userMessageFor(e)),
        data: (e) {
          if (e == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This examination could not be found.',
            );
          }
          if (!e.status.isConfigurable) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message:
                  'Only a draft or scheduled examination can be edited. '
                  'Withdraw or reopen it to correct results.',
            );
          }
          if (!_loaded) _load(e);
          return _body(e);
        },
      );
    }
    return _body(null);
  }

  Widget _body(Examination? existing) {
    final tt = widget.tt;
    final classes = ref
        .watch(
          classesProvider((
            schoolId: tt.schoolId,
            branchId: tt.branchId,
            academicYearId: tt.year.academicYearId,
          )),
        )
        .value;
    final sections = _classId == null
        ? null
        : ref
              .watch(
                sectionsProvider((
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                  academicYearId: tt.year.academicYearId,
                  classId: _classId!,
                )),
              )
              .value;
    final schemes = ref
        .watch(schemesProvider((schoolId: tt.schoolId, branchId: tt.branchId)))
        .value
        ?.where((s) => s.active || s.schemeId == _schemeId)
        .toList();
    if (schemes != null && schemes.isEmpty) {
      return EmptyView(
        icon: Icons.rule,
        message:
            'Create a grading scheme first. Examinations are graded by a '
            'scheme the school defines.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.examSchemes),
          child: const Text('Grading schemes'),
        ),
      );
    }
    String className() =>
        classes?.where((c) => c.classId == _classId).firstOrNull?.name ??
        _classId ??
        '';
    String classLabel() {
      final sec = _sectionId == null
          ? null
          : sections?.where((s) => s.sectionId == _sectionId).firstOrNull?.name;
      return sec == null ? className() : '${className()} – $sec';
    }

    return PageColumn(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              title: 'Examination',
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_editing,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      helperText: _editing
                          ? 'The name is fixed once created.'
                          : 'For example "Half-yearly 2026".',
                    ),
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Enter at least 3 characters.'
                        : null,
                  ),
                  DropdownButtonFormField<ExamType>(
                    value: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final t in ExamType.values)
                        DropdownMenuItem(value: t, child: Text(t.displayName)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _type = v!),
                  ),
                  TextFormField(
                    controller: _description,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Who it is for',
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Class'),
                    validator: (v) => v == null ? 'Choose the class.' : null,
                    items: [
                      for (final c in classes ?? [])
                        DropdownMenuItem(value: c.classId, child: Text(c.name)),
                    ],
                    onChanged: _editing || _saving
                        ? null
                        : (v) => setState(() {
                            _classId = v;
                            _sectionId = null;
                          }),
                  ),
                  if (sections != null)
                    DropdownButtonFormField<String?>(
                      value: _sectionId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All sections'),
                        ),
                        for (final s in sections)
                          DropdownMenuItem(
                            value: s.sectionId,
                            child: Text(s.name),
                          ),
                      ],
                      onChanged: _editing || _saving
                          ? null
                          : (v) => setState(() => _sectionId = v),
                    ),
                  DropdownButtonFormField<String>(
                    value: schemes?.any((s) => s.schemeId == _schemeId) == true
                        ? _schemeId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Grading scheme',
                    ),
                    validator: (v) =>
                        v == null ? 'Choose a grading scheme.' : null,
                    items: [
                      for (final s in schemes ?? [])
                        DropdownMenuItem(
                          value: s.schemeId,
                          child: Text(s.name),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _schemeId = v),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Dates',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pick(true),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _start == null
                          ? 'Start date'
                          : formatDateKey(AttendanceDate.key(_start!)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pick(false),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _end == null
                          ? 'End date'
                          : formatDateKey(AttendanceDate.key(_end!)),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Instructions',
              child: TextFormField(
                controller: _instructions,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Instructions and remarks',
                  alignLabelWithHint: true,
                ),
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
            Row(
              children: [
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _save(existing, classLabel()),
                  child: Text(
                    existing == null ? 'Create examination' : 'Save changes',
                  ),
                ),
                if (_saving)
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
    );
  }
}
