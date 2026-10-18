import '../../../../core/regional/school_time.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../homework/domain/homework_repositories.dart' show HomeworkPaths;
import '../../../homework/presentation/providers/homework_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/announcement.dart';
import '../../domain/announcement_file_policy.dart';
import '../../domain/announcement_save_flow.dart';
import '../../domain/attachment_upload_controller.dart';
import '../providers/announcement_providers.dart';
import '../widgets/announcement_attachments.dart';

/// `/announcements/new` and `/announcements/edit/:announcementId`.
///
/// Who may address whom is shaped here and enforced by the rules: a teacher
/// only to a section they are class teacher of; a branch admin to their
/// branch; only a school admin to the whole school. A published
/// announcement's audience is fixed; its text, files and expiry may be
/// updated (optionally notifying the audience again). Preview comes before
/// publishing.
class AnnouncementFormPage extends StatelessWidget {
  final String? announcementId;
  final String? branchId;

  const AnnouncementFormPage({super.key, this.announcementId, this.branchId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          announcementId == null ? 'New announcement' : 'Edit announcement',
        ),
      ),
      body: TimetableScope(
        showYearSelector: false,
        builder: (context, tt) => _Form(tt: tt, announcementId: announcementId),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final String? announcementId;

  const _Form({required this.tt, required this.announcementId});

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final String _newId = Announcement.newId();

  AnnouncementAudience? _audience;
  String? _classId;
  String? _sectionId;
  DateTime? _publishAt;
  DateTime? _expiresAt;
  bool _notify = true;
  late final AttachmentUploadController _files;

  /// True once the announcement exists in Firestore, so its files may be
  /// uploaded (the Storage rules require the announcement to exist).
  bool _draftSaved = false;
  bool _completed = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _ownStaffId;
  bool _ready = false;

  bool get _editing => widget.announcementId != null;
  UserRole get _role => widget.tt.tenant.role;
  bool get _isTeacher => _role == UserRole.teacher;

  String get _id => widget.announcementId ?? _newId;

  @override
  void initState() {
    super.initState();
    _files = AttachmentUploadController(
      ref.read(announcementFileUploaderProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
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
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    // Files uploaded but never saved with the announcement are unreferenced.
    if (!_completed) _files.discardUnsaved();
    _files.dispose();
    super.dispose();
  }

  List<AnnouncementAudience> get _allowedAudiences => switch (_role) {
    UserRole.teacher => const [AnnouncementAudience.section],
    UserRole.branchAdmin => const [
      AnnouncementAudience.branch,
      AnnouncementAudience.staff,
      AnnouncementAudience.parents,
      AnnouncementAudience.classGroup,
      AnnouncementAudience.section,
    ],
    _ => AnnouncementAudience.values,
  };

  void _load(Announcement a) {
    _loaded = true;
    _title.text = a.title;
    _body.text = a.body;
    _audience = a.audience;
    _classId = a.classId;
    _sectionId = a.sectionId;
    _publishAt = a.publishAt;
    _expiresAt = a.expiresAt;
    _draftSaved = true;
    _files.loadExisting(a.attachments);
  }

  Announcement _build({Announcement? existing}) {
    final tt = widget.tt;
    return Announcement(
      announcementId: _id,
      schoolId: tt.schoolId,
      branchId: tt.branchId,
      academicYearId: _audience?.needsClass == true
          ? tt.year.academicYearId
          : null,
      audience: _audience ?? AnnouncementAudience.branch,
      classId: _audience?.needsClass == true ? _classId : null,
      sectionId: _audience?.needsSection == true ? _sectionId : null,
      audienceLabel: existing?.audienceLabel,
      title: _title.text.trim(),
      body: _body.text.trim(),
      attachments: _files.attachments,
      publishAt: _publishAt,
      expiresAt: _expiresAt,
      status: existing?.status ?? AnnouncementStatus.draft,
      revision: existing?.revision ?? 1,
      authorId: existing?.authorId ?? tt.userId,
      authorName: existing?.authorName ?? tt.userName,
      authorRole: existing?.authorRole ?? tt.tenant.role.wireValue,
    );
  }

  /// Date and time are entered as the school's wall clock and stored as the
  /// real moment they denote in the school's time zone.
  Future<DateTime?> _pickDateTime(DateTime? initialInstant) async {
    final now = SchoolTime.wallNow();
    final initial = initialInstant == null
        ? null
        : SchoolTime.wallOf(initialInstant);
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return SchoolTime.instantFromWall(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  String _pathFor(String fileName) => HomeworkPaths.announcementFile(
    widget.tt.schoolId,
    widget.tt.branchId,
    _id,
    fileName,
  );

  Future<bool> _uploadNow() =>
      _files.uploadAll(pathFor: _pathFor, uploadedBy: widget.tt.userId);

  Future<void> _pick({required bool images}) async {
    if (_saving || _files.isUploading) return;
    final full = AnnouncementFilePolicy.validateCount(
      current: _files.items.length,
      adding: 1,
    );
    if (full != null) return setState(() => _error = full);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: images
          ? AnnouncementFilePolicy.imageExtensions
          : AnnouncementFilePolicy.documentExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    final problems = <String>[
      for (final f in result.files)
        if (f.bytes == null) '${f.name}: could not be read.',
      ..._files.add([
        for (final f in result.files)
          if (f.bytes != null) (name: f.name, bytes: f.bytes!),
      ]),
    ];
    setState(() => _error = problems.isEmpty ? null : problems.join('\n'));
    // An announcement that already exists can take its files straight away;
    // a new one uploads them when it is saved.
    if (_draftSaved && _files.waiting.isNotEmpty) await _uploadNow();
  }

  Future<void> _retry(AttachmentItem item) async {
    if (!_draftSaved) return;
    final ok = await _files.retry(
      item,
      pathFor: _pathFor,
      uploadedBy: widget.tt.userId,
    );
    if (ok && mounted && !_files.hasUnresolved) setState(() => _error = null);
  }

  Future<void> _save(Announcement? existing, {required bool publish}) async {
    if (_saving || _files.isUploading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tt = widget.tt;
    final published =
        existing != null && existing.status == AnnouncementStatus.published;
    if (published && _files.hasUnresolved) {
      return setState(
        () => _error =
            'Some attachments are not uploaded. Retry or remove them first.',
      );
    }
    final problem = _build(existing: existing).validate(now: DateTime.now());
    if (problem != null) return setState(() => _error = problem);
    if (publish) {
      final preview = _build(existing: existing);
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AnnouncementPreviewScreen(
            announcement: preview,
            scheduledFor: _publishAt,
            pendingFileNames: [
              for (final i in _files.items)
                if (!i.isUploaded) i.name,
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome =
          await AnnouncementSaveFlow(
            ref.read(announcementRepositoryProvider),
            _files,
          ).run(
            build: () => _build(existing: existing),
            editingPublished: published,
            publish: publish,
            publishAt: _publishAt ?? DateTime.now(),
            notify: _notify,
            actor: actorFor(tt.tenant),
            pathFor: _pathFor,
            uploadedBy: tt.userId,
            onDraftSaved: () => _draftSaved = true,
          );
      if (outcome == AnnouncementSaveOutcome.uploadsFailed) {
        if (mounted) {
          setState(
            () => _error =
                '${_files.failed.length} attachment(s) could not be '
                'uploaded. Retry them or remove them, then '
                '${publish ? 'publish' : 'save'} again. Nothing was '
                'published.',
          );
        }
        return;
      }
      _completed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish ? 'Announcement published.' : 'Announcement saved.',
          ),
        ),
      );
      context.go(AppRoutes.announcements);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (!_editing) return _body_(null);
    final a = ref.watch(
      announcementProvider((
        schoolId: widget.tt.schoolId,
        branchId: widget.tt.branchId,
        announcementId: widget.announcementId!,
      )),
    );
    return a.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (existing) {
        if (existing == null) {
          return const EmptyView(
            icon: Icons.search_off,
            message: 'This announcement could not be found.',
          );
        }
        if (existing.status == AnnouncementStatus.archived) {
          return const EmptyView(
            icon: Icons.inventory_2_outlined,
            message: 'Archived announcements cannot be edited.',
          );
        }
        if (!_loaded) _load(existing);
        return _body_(existing);
      },
    );
  }

  Widget _body_(Announcement? existing) {
    final tt = widget.tt;
    final published = existing?.status == AnnouncementStatus.published;
    _audience ??= _allowedAudiences.first;

    // A teacher's choices: the sections they are class teacher of.
    final facts = _isTeacher && _ownStaffId != null
        ? ref
              .watch(
                yearAssignmentsProvider((
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                  academicYearId: tt.year.academicYearId,
                )),
              )
              .value
        : null;
    final classTeacherSections = [
      for (final f in facts ?? const [])
        if (f.isClassTeacher && f.teacherStaffId == _ownStaffId) f,
    ];
    if (_isTeacher && _ownStaffId == null) {
      return const EmptyView(
        icon: Icons.link_off,
        message:
            "Your account isn't linked to a staff record, so you can't "
            'post announcements.',
      );
    }
    if (_isTeacher && facts != null && classTeacherSections.isEmpty) {
      return const EmptyView(
        icon: Icons.lock_outline,
        message:
            'Teachers can post announcements to a section they are class '
            'teacher of. You are not a class teacher of any section this '
            'year.',
      );
    }

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
    final classNames = {for (final c in classes ?? []) c.classId: c.name};

    return PageColumn(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              title: 'Audience',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<AnnouncementAudience>(
                    value: _audience,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Send to'),
                    items: [
                      for (final a in _allowedAudiences)
                        DropdownMenuItem(value: a, child: Text(a.displayName)),
                    ],
                    onChanged: _editing || _saving
                        ? null
                        : (v) => setState(() {
                            _audience = v;
                            _classId = null;
                            _sectionId = null;
                          }),
                  ),
                  if (_audience == AnnouncementAudience.all)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'A school-wide announcement is stored with this '
                        'branch and reaches the people of this branch. '
                        'Post it in each branch to reach all of them.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (_audience?.needsClass == true) ...[
                    const SizedBox(height: AppSpacing.sm),
                    if (_isTeacher)
                      DropdownButtonFormField<String>(
                        value: _sectionId == null
                            ? null
                            : '${_classId!}/$_sectionId',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Your section',
                        ),
                        validator: (v) =>
                            v == null ? 'Choose a section.' : null,
                        items: [
                          for (final f in classTeacherSections)
                            DropdownMenuItem(
                              value: '${f.classId}/${f.sectionId}',
                              child: Text(
                                '${classNames[f.classId] ?? f.classId} – '
                                '${f.sectionId}',
                              ),
                            ),
                        ],
                        onChanged: _editing || _saving
                            ? null
                            : (v) => setState(() {
                                final parts = v!.split('/');
                                _classId = parts[0];
                                _sectionId = parts[1];
                              }),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        value: _classId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Class'),
                        validator: (v) => v == null ? 'Choose a class.' : null,
                        items: [
                          for (final c in classes ?? [])
                            DropdownMenuItem(
                              value: c.classId,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: _editing || _saving
                            ? null
                            : (v) => setState(() {
                                _classId = v;
                                _sectionId = null;
                              }),
                      ),
                      if (_audience?.needsSection == true && sections != null)
                        DropdownButtonFormField<String>(
                          value: _sectionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                          ),
                          validator: (v) =>
                              v == null ? 'Choose a section.' : null,
                          items: [
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
                    ],
                  ],
                  if (published)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'The audience of a published announcement is fixed.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Message',
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Enter at least 3 characters.'
                        : null,
                  ),
                  TextFormField(
                    controller: _body,
                    maxLength: 4000,
                    minLines: 5,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Write the message.' : null,
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'When',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!published) ...[
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final d = await _pickDateTime(_publishAt);
                              if (d != null) setState(() => _publishAt = d);
                            },
                      icon: const Icon(Icons.schedule_send_outlined),
                      label: Text(
                        _publishAt == null
                            ? 'Publish immediately'
                            : 'Publish ${formatInstant(_publishAt)}',
                      ),
                    ),
                    if (_publishAt != null)
                      TextButton(
                        onPressed: () => setState(() => _publishAt = null),
                        child: const Text('Publish immediately'),
                      ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final d = await _pickDateTime(_expiresAt);
                            if (d != null) setState(() => _expiresAt = d);
                          },
                    icon: const Icon(Icons.event_busy_outlined),
                    label: Text(
                      _expiresAt == null
                          ? 'No expiry'
                          : 'Expires ${formatInstant(_expiresAt)}',
                    ),
                  ),
                  if (_expiresAt != null)
                    TextButton(
                      onPressed: () => setState(() => _expiresAt = null),
                      child: const Text('Remove expiry'),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Attachments',
              child: AnnouncementAttachmentsEditor(
                controller: _files,
                enabled: !_saving,
                onPickImages: () => _pick(images: true),
                onPickDocuments: () => _pick(images: false),
                onRetry: _retry,
              ),
            ),
            if (published)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _notify,
                onChanged: (v) => setState(() => _notify = v ?? true),
                title: const Text('Notify the audience about this update'),
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
                if (published)
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(existing, publish: false),
                    child: const Text('Save update'),
                  )
                else ...[
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _save(existing, publish: false),
                    child: const Text('Save draft'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _save(existing, publish: true),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview & publish'),
                  ),
                ],
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

/// What the audience will see, before anything is published.
class AnnouncementPreviewScreen extends StatelessWidget {
  final Announcement announcement;
  final DateTime? scheduledFor;
  final List<String> pendingFileNames;

  const AnnouncementPreviewScreen({
    super.key,
    required this.announcement,
    this.scheduledFor,
    this.pendingFileNames = const [],
  });

  @override
  Widget build(BuildContext context) {
    final a = announcement;
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
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Back to edit'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.campaign),
                label: Text(scheduledFor == null ? 'Publish now' : 'Schedule'),
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
              title: 'Goes to',
              child: Text(a.audienceLabel ?? a.audience.displayName),
            ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(a.body),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    scheduledFor == null
                        ? 'Visible immediately.'
                        : 'Visible from ${formatInstant(scheduledFor)}.',
                  ),
                  if (a.expiresAt != null)
                    Text('Expires ${formatInstant(a.expiresAt)}.'),
                  for (final n in [
                    ...a.attachments.map((f) => f.name),
                    ...pendingFileNames,
                  ])
                    Text('📎 $n'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
