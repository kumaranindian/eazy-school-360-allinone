import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/weekday.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/file_attachment.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_repositories.dart' show HomeworkPaths;
import '../../domain/homework_rules.dart';
import '../providers/homework_options.dart';
import '../providers/homework_providers.dart';
import '../widgets/homework_widgets.dart';

/// `/homework/new` and `/homework/edit/:homeworkId`.
///
/// Creating: choose the sections and subjects (a teacher sees only their own
/// assignments), fill the details, then either save a draft or preview and
/// publish. One homework document is created per section, under a shared
/// batch id so a retry cannot duplicate it. Editing a draft changes
/// everything; a published homework allows only the instructions, files and
/// an *extension* of the deadline — marks, policy and audience are fixed once
/// families may have started.
class HomeworkFormPage extends StatelessWidget {
  final String? homeworkId;

  const HomeworkFormPage({super.key, this.homeworkId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(homeworkId == null ? 'New homework' : 'Edit homework'),
      ),
      body: TimetableScope(
        showYearSelector: homeworkId == null,
        builder: (context, tt) => _HomeworkForm(tt: tt, homeworkId: homeworkId),
      ),
    );
  }
}

class _HomeworkForm extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final String? homeworkId;

  const _HomeworkForm({required this.tt, required this.homeworkId});

  @override
  ConsumerState<_HomeworkForm> createState() => _HomeworkFormState();
}

class _HomeworkFormState extends ConsumerState<_HomeworkForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _marks = TextEditingController();
  final _batchBase =
      'hb${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  final Set<String> _selected = {};
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  bool _requiresSubmission = true;
  bool _allowFiles = true;
  bool _allowLate = false;
  bool _allowResubmission = true;
  List<FileAttachment> _attachments = [];
  final List<PendingFile> _pending = [];
  bool _loadedExisting = false;
  bool _saving = false;
  String? _error;
  String? _ownStaffId;
  bool _staffReady = false;

  bool get _isTeacher => widget.tt.tenant.role == UserRole.teacher;
  bool get _editing => widget.homeworkId != null;

  HomeworkKey get _key => (
    schoolId: widget.tt.schoolId,
    branchId: widget.tt.branchId,
    homeworkId: widget.homeworkId ?? '',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveStaff());
  }

  Future<void> _resolveStaff() async {
    if (_isTeacher) {
      try {
        final staff = await readAlive(
          ref,
          ownStaffProvider((
            schoolId: widget.tt.schoolId,
            branchId: widget.tt.branchId,
            userId: widget.tt.userId,
          )),
        );
        _ownStaffId = staff?.staffId;
      } catch (_) {}
    }
    if (mounted) setState(() => _staffReady = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _marks.dispose();
    super.dispose();
  }

  void _loadFrom(Homework h) {
    _loadedExisting = true;
    _title.text = h.title;
    _description.text = h.description;
    _marks.text = h.maxMarks?.toString() ?? '';
    final d = AttendanceDate.parse(h.dueDateKey);
    _dueDate = DateTime(d.year, d.month, d.day);
    _dueTime = h.dueTimeMin == null
        ? null
        : TimeOfDay(hour: h.dueTimeMin! ~/ 60, minute: h.dueTimeMin! % 60);
    _requiresSubmission = h.requiresSubmission;
    _allowFiles = h.allowFiles;
    _allowLate = h.allowLate;
    _allowResubmission = h.allowResubmission;
    _attachments = [...h.attachments];
  }

  Future<void> _pickDate({DateTime? first}) async {
    final today = SchoolTime.wallNow();
    final start = first ?? DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: (_dueDate != null && !_dueDate!.isBefore(start))
          ? _dueDate!
          : start,
      firstDate: start,
      lastDate: DateTime(today.year + 2),
      helpText: 'Due date',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 17, minute: 0),
      helpText: 'Due time (optional)',
    );
    if (picked != null) setState(() => _dueTime = picked);
  }

  int? get _dueTimeMin =>
      _dueTime == null ? null : _dueTime!.hour * 60 + _dueTime!.minute;

  Future<void> _addFiles(Homework? existing) async {
    final remaining =
        FilePolicy.maxFilesPerRecord - _attachments.length - _pending.length;
    final files = await pickValidatedFiles(
      remaining: remaining,
      onProblem: (m) {
        if (mounted) setState(() => _error = m);
      },
    );
    if (files.isEmpty || !mounted) return;
    if (existing == null) {
      setState(() {
        _pending.addAll(files);
        _error = null;
      });
      return;
    }
    // Editing: the record exists, so upload straight away.
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final f in files) {
        final uploaded = await ref
            .read(homeworkFileStoreProvider)
            .upload(
              path: HomeworkPaths.homeworkFile(
                existing.schoolId,
                existing.branchId,
                existing.homeworkId,
                uniqueFileName(f.name),
              ),
              fileName: f.name,
              bytes: f.bytes,
              uploadedBy: widget.tt.userId,
            );
        _attachments.add(uploaded);
      }
    } catch (e) {
      _error = userMessageFor(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The homework documents this form would create.
  List<Homework> _buildNew(List<HomeworkOption> options) {
    final today = AttendanceDate.key(SchoolTime.wallNow());
    final dueKey = AttendanceDate.key(_dueDate!);
    final max = int.tryParse(_marks.text.trim());
    return [
      for (final o in options)
        if (_selected.contains(o.key))
          Homework(
            homeworkId: Homework.idFor(
              '${_batchBase}_${o.subjectId}',
              o.sectionId,
            ),
            batchId: '${_batchBase}_${o.subjectId}',
            schoolId: widget.tt.schoolId,
            branchId: widget.tt.branchId,
            academicYearId: widget.tt.year.academicYearId,
            classId: o.classId,
            sectionId: o.sectionId,
            classLabel: o.classLabel,
            subjectId: o.subjectId,
            subjectName: o.subjectName,
            teacherStaffId: o.teacherStaffId,
            teacherName: o.teacherName,
            title: _title.text.trim(),
            description: _description.text.trim(),
            assignedDateKey: today,
            dueDateKey: dueKey,
            dueTimeMin: _dueTimeMin,
            dueAt: Homework.dueInstant(dueKey, _dueTimeMin),
            maxMarks: max,
            requiresSubmission: _requiresSubmission,
            allowFiles: _allowFiles,
            allowLate: _allowLate,
            allowResubmission: _allowResubmission,
          ),
    ];
  }

  String? _validateCommon() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return 'Fix the highlighted fields.';
    }
    if (_dueDate == null) return 'Choose a due date.';
    if (_marks.text.trim().isNotEmpty &&
        int.tryParse(_marks.text.trim()) == null) {
      return 'Maximum marks must be a whole number.';
    }
    return null;
  }

  Future<void> _create(
    List<HomeworkOption> options, {
    required bool publish,
  }) async {
    if (_saving) return;
    final common = _validateCommon();
    if (common != null) return setState(() => _error = common);
    if (_selected.isEmpty) {
      return setState(
        () => _error = 'Choose at least one section and subject.',
      );
    }
    final list = _buildNew(options);
    final todayKey = AttendanceDate.key(SchoolTime.wallNow());
    for (final h in list) {
      final problem = HomeworkRules.validate(h, todayKey: todayKey);
      if (problem != null) return setState(() => _error = problem);
      if (publish) {
        final p = HomeworkRules.checkPublish(h, now: DateTime.now());
        if (p != null) return setState(() => _error = p);
      }
    }
    if (publish) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => HomeworkPreviewScreen(
            homework: list,
            pendingFileNames: [for (final f in _pending) f.name],
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final actor = actorFor(widget.tt.tenant);
    final repo = ref.read(homeworkRepositoryProvider);
    final store = ref.read(homeworkFileStoreProvider);
    var fileFailures = 0;
    var publishFailures = 0;
    try {
      await repo.createDrafts(homework: list, actor: actor);
      for (var i = 0; i < list.length; i++) {
        var h = list[i];
        if (_pending.isNotEmpty) {
          final uploaded = <FileAttachment>[];
          for (final f in _pending) {
            try {
              uploaded.add(
                await store.upload(
                  path: HomeworkPaths.homeworkFile(
                    h.schoolId,
                    h.branchId,
                    h.homeworkId,
                    uniqueFileName(f.name),
                  ),
                  fileName: f.name,
                  bytes: f.bytes,
                  uploadedBy: actor.userId,
                ),
              );
            } catch (_) {
              fileFailures++;
            }
          }
          if (uploaded.isNotEmpty) {
            h = h.copyWith(attachments: uploaded);
            await repo.saveDraft(homework: h, actor: actor);
          }
        }
        if (publish) {
          try {
            // Re-read the draft's revision inside the repository.
            await repo.publish(homework: h, actor: actor);
          } catch (_) {
            publishFailures++;
          }
        }
      }
      if (!mounted) return;
      final parts = <String>[
        publish && publishFailures == 0
            ? 'Published to ${list.length} section(s).'
            : 'Saved ${list.length} draft(s).',
        if (publishFailures > 0)
          '$publishFailures could not be published — open the draft to retry.',
        if (fileFailures > 0)
          '$fileFailures file(s) failed to upload — edit the draft to add them again.',
      ];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(parts.join(' '))));
      context.go(AppRoutes.homework);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveExisting(Homework h) async {
    if (_saving) return;
    final common = _validateCommon();
    if (common != null) return setState(() => _error = common);
    setState(() {
      _saving = true;
      _error = null;
    });
    final actor = actorFor(widget.tt.tenant);
    final repo = ref.read(homeworkRepositoryProvider);
    try {
      final dueKey = AttendanceDate.key(_dueDate!);
      final dueAt = Homework.dueInstant(dueKey, _dueTimeMin);
      if (h.status == HomeworkStatus.draft) {
        final edited = h.copyWith(
          title: _title.text.trim(),
          description: _description.text.trim(),
          dueDateKey: dueKey,
          dueTimeMin: _dueTimeMin,
          clearDueTime: _dueTimeMin == null,
          dueAt: dueAt,
          attachments: _attachments,
          requiresSubmission: _requiresSubmission,
          allowFiles: _allowFiles,
          allowLate: _allowLate,
          allowResubmission: _allowResubmission,
        );
        final problem = HomeworkRules.validate(
          edited,
          todayKey: AttendanceDate.key(SchoolTime.wallNow()),
        );
        if (problem != null) {
          setState(() => _error = problem);
          return;
        }
        await repo.saveDraft(homework: edited, actor: actor);
      } else {
        final dueChanged = !dueAt.isAtSameMomentAs(h.dueAt);
        if (dueChanged) {
          final problem = HomeworkRules.checkDueChange(h, dueAt);
          if (problem != null) {
            setState(() => _error = problem);
            return;
          }
        }
        final textChanged =
            _description.text.trim() != h.description.trim() ||
            _attachments.length != h.attachments.length;
        if (textChanged) {
          await repo.editPublished(
            homework: h,
            description: _description.text.trim(),
            attachments: _attachments,
            actor: actor,
          );
        }
        if (dueChanged) {
          // Re-read so the deadline change builds on the new revision.
          await repo.changeDue(
            homework: h,
            dueDateKey: dueKey,
            dueTimeMin: _dueTimeMin,
            dueAt: dueAt,
            actor: actor,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Homework saved.')));
      context.go(
        AppRoutes.homeworkDetail.replaceFirst(':homeworkId', h.homeworkId),
      );
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    if (!_staffReady) return const Center(child: CircularProgressIndicator());
    if (_isTeacher && _ownStaffId == null) {
      return const EmptyView(
        icon: Icons.link_off,
        message:
            "Your account isn't linked to a staff record, so you can't set "
            'homework. Please contact the school office.',
      );
    }
    if (_editing) {
      final hw = ref.watch(homeworkProvider(_key));
      return hw.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: userMessageFor(e)),
        data: (h) {
          if (h == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This homework could not be found.',
            );
          }
          if (h.status == HomeworkStatus.closed ||
              h.status == HomeworkStatus.archived) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message: 'Closed and archived homework cannot be edited.',
            );
          }
          if (!_loadedExisting) _loadFrom(h);
          return _formBody(h, const []);
        },
      );
    }
    final options = ref.watch(
      homeworkOptionsProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        academicYearId: tt.year.academicYearId,
        teacherStaffId: _isTeacher ? _ownStaffId : null,
      )),
    );
    return options.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.assignment_ind_outlined,
            message:
                'No subject assignments found for this academic year. '
                'Homework can only be set for the sections and subjects a '
                'teacher is assigned to.',
          );
        }
        return _formBody(null, list);
      },
    );
  }

  Widget _formBody(Homework? existing, List<HomeworkOption> options) {
    final published = existing?.status == HomeworkStatus.published;
    final fixed = published; // policy/marks/title fixed once published
    final todayStart = SchoolTime.wallNow();
    return PageColumn(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (published)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('This homework is published'),
                  subtitle: Text(
                    'You can update the instructions and files, or extend '
                    'the deadline. Title, marks and policy are fixed.',
                  ),
                ),
              ),
            if (existing == null) ...[
              _quickPick(options),
              SectionCard(
                title: 'Sections and subjects',
                child: Column(
                  children: [
                    for (final o in options)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _selected.contains(o.key),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                v == true
                                    ? _selected.add(o.key)
                                    : _selected.remove(o.key);
                              }),
                        title: Text('${o.classLabel} — ${o.subjectName}'),
                        subtitle: _isTeacher || o.teacherName.isEmpty
                            ? null
                            : Text(o.teacherName),
                      ),
                  ],
                ),
              ),
            ] else
              SectionCard(
                title: 'For',
                child: Text(
                  '${existing.classLabel ?? existing.classId} — '
                  '${existing.subjectName} (${existing.teacherName})',
                ),
              ),
            SectionCard(
              title: 'Details',
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    enabled: !fixed,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Enter at least 3 characters.'
                        : null,
                  ),
                  TextFormField(
                    controller: _description,
                    maxLength: 4000,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Instructions',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Deadline',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickDate(
                            first: existing == null
                                ? null
                                : _atMidnight(existing.dueAt, todayStart),
                          ),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _dueDate == null
                          ? 'Choose due date'
                          : formatDateKey(AttendanceDate.key(_dueDate!)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _dueTime == null
                          ? 'End of day (set a time)'
                          : _dueTime!.format(context),
                    ),
                  ),
                  if (_dueTime != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _dueTime = null),
                      child: const Text('Clear time'),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Marks and submission',
              child: Column(
                children: [
                  TextFormField(
                    controller: _marks,
                    enabled: !fixed,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum marks (leave empty if not graded)',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      if (n == null || n < 1 || n > 1000) {
                        return 'Enter a whole number from 1 to 1000.';
                      }
                      return null;
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Students submit work'),
                    value: _requiresSubmission,
                    onChanged: fixed || _saving
                        ? null
                        : (v) => setState(() => _requiresSubmission = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow file attachments'),
                    value: _allowFiles,
                    onChanged: fixed || _saving || !_requiresSubmission
                        ? null
                        : (v) => setState(() => _allowFiles = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Accept late submissions'),
                    value: _allowLate,
                    onChanged: fixed || _saving || !_requiresSubmission
                        ? null
                        : (v) => setState(() => _allowLate = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow resubmission before the deadline'),
                    value: _allowResubmission,
                    onChanged: fixed || _saving || !_requiresSubmission
                        ? null
                        : (v) => setState(() => _allowResubmission = v),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Files',
              actions: [
                TextButton.icon(
                  onPressed: _saving ? null : () => _addFiles(existing),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add files'),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AttachmentList(
                    attachments: _attachments,
                    onRemove: _saving
                        ? null
                        : (f) => setState(() => _attachments.remove(f)),
                  ),
                  for (final f in _pending)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.upload_file),
                      title: Text(f.name),
                      subtitle: Text(
                        '${formatBytes(f.bytes.length)} · uploads when you save',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${f.name}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _pending.remove(f)),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'PDF, JPG, PNG, TXT or DOCX, up to 10 MB each, at most '
                    '${FilePolicy.maxFilesPerRecord} files. Files are not '
                    'scanned for malware.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                if (existing == null) ...[
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _create(options, publish: false),
                    child: const Text('Save draft'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _create(options, publish: true),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview & publish'),
                  ),
                ] else
                  FilledButton(
                    onPressed: _saving ? null : () => _saveExisting(existing),
                    child: const Text('Save changes'),
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

  DateTime _atMidnight(DateTime due, DateTime today) {
    final d = DateTime(due.year, due.month, due.day);
    return d.isBefore(DateTime(today.year, today.month, today.day))
        ? DateTime(today.year, today.month, today.day)
        : d;
  }

  /// Subjects timetabled for the teacher today (from the published
  /// timetable), as one-tap choices. The timetable is a convenience, not a
  /// requirement: every assigned subject stays selectable below.
  Widget _quickPick(List<HomeworkOption> options) {
    if (!_isTeacher || _ownStaffId == null) return const SizedBox.shrink();
    final tt = widget.tt;
    final bundles = ref
        .watch(
          teacherBundlesProvider((
            schoolId: tt.schoolId,
            branchId: tt.branchId,
            academicYearId: tt.year.academicYearId,
            teacherStaffId: _ownStaffId!,
          )),
        )
        .value;
    if (bundles == null) return const SizedBox.shrink();
    final today = Weekday.fromDateTimeWeekday(SchoolTime.wallNow().weekday);
    final scheduled = <String, HomeworkOption>{};
    for (final b in bundles) {
      for (final e in b.entries) {
        if (e.weekday != today || e.teacherStaffId != _ownStaffId) continue;
        for (final o in options) {
          if (o.classId == e.classId &&
              o.sectionId == e.sectionId &&
              o.subjectId == e.subjectId) {
            scheduled[o.key] = o;
          }
        }
      }
    }
    if (scheduled.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'Taught today',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final o in scheduled.values)
            FilterChip(
              label: Text('${o.classLabel} · ${o.subjectName}'),
              selected: _selected.contains(o.key),
              onSelected: _saving
                  ? null
                  : (v) => setState(
                      () => v ? _selected.add(o.key) : _selected.remove(o.key),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Shows what families will see, and whom it goes to, before anything is
/// written. Returns true to publish, false/null to go back and edit.
class HomeworkPreviewScreen extends StatelessWidget {
  final List<Homework> homework;
  final List<String> pendingFileNames;

  const HomeworkPreviewScreen({
    super.key,
    required this.homework,
    this.pendingFileNames = const [],
  });

  @override
  Widget build(BuildContext context) {
    final first = homework.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review before publishing'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to editing',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          // Wraps onto a second line when the two buttons do not fit side by
          // side (narrow phone, large text) instead of overflowing.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Back to edit'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.public),
                label: Text('Publish to ${homework.length} section(s)'),
              ),
            ],
          ),
        ),
      ),
      body: PageColumn(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              title: 'Who will see it',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in homework)
                    Text(
                      '• ${h.classLabel ?? h.classId} — ${h.subjectName} '
                      '(${h.teacherName})',
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Parents and students of these sections are notified. '
                    'Once published, the title, marks and policy are fixed.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SectionCard(
              title: first.title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dueLabel(first)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    first.description.isEmpty
                        ? 'No instructions.'
                        : first.description,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      StatusPill(
                        label: first.maxMarks == null
                            ? 'Not graded'
                            : 'Out of ${first.maxMarks}',
                      ),
                      StatusPill(
                        label: first.requiresSubmission
                            ? 'Submission required'
                            : 'No submission',
                      ),
                      if (first.requiresSubmission && first.allowFiles)
                        const StatusPill(label: 'Files allowed'),
                      if (first.requiresSubmission)
                        StatusPill(
                          label: first.allowLate
                              ? 'Late accepted'
                              : 'No late work',
                        ),
                      if (first.requiresSubmission)
                        StatusPill(
                          label: first.allowResubmission
                              ? 'Resubmission allowed'
                              : 'One submission',
                        ),
                    ],
                  ),
                  if (first.attachments.isNotEmpty ||
                      pendingFileNames.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    for (final n in [
                      ...first.attachments.map((a) => a.name),
                      ...pendingFileNames,
                    ])
                      Text('📎 $n'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
