import 'dart:convert';
import '../../../users/presentation/providers/login_access_providers.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../shared/bulk_import/bulk_rows_view.dart';
import '../../../../shared/bulk_import/login_access_next_step.dart';
import '../../../../shared/branding/acting_branch_banner.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../data/bulk_student_importer.dart';
import '../../domain/bulk_student_import.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';

/// Bulk admission from a CSV sheet: download the sample → fill it → pick the
/// academic year → upload → review the per-row preview → import the valid
/// rows. Failed rows can be downloaded (with an `error` column) to fix and
/// re-upload. See `docs/bulk-student-upload.md`.
class StudentBulkImportPage extends ConsumerStatefulWidget {
  const StudentBulkImportPage({super.key});

  @override
  ConsumerState<StudentBulkImportPage> createState() =>
      _StudentBulkImportPageState();
}

class _StudentBulkImportPageState extends ConsumerState<StudentBulkImportPage> {
  String? _academicYearId;
  String? _fileName;
  String? _csvText;
  BulkStudentParseResult? _parsed;
  List<BulkStudentRow> _rows = const [];
  List<BulkImportRowResult>? _results;
  final Map<String, bool> _availability = {};
  final Map<String, bool> _parentEmailInUse = {};

  bool _checking = false;
  bool _importing = false;
  int _progressDone = 0;
  int _progressTotal = 0;

  Future<void> _saveCsv(String fileName, String content) async {
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      AppLogger.debug(
        'Bulk import: saved $fileName -> $saved',
        tag: 'BulkImport',
      );
      if (mounted && saved != null) context.showSnackBar('Saved $fileName');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Bulk import: could not save $fileName',
        tag: 'BulkImport',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        context.showSnackBar('Could not save the file.', isError: true);
      }
    }
  }

  Future<PlacementLookup> _loadPlacements(
    String schoolId,
    String branchId,
    String yearId,
  ) async {
    final repo = ref.read(academicStructureRepositoryProvider);
    final classes = (await repo.watchClasses(schoolId, branchId, yearId).first)
        .where((c) => c.status == ActivationStatus.active);
    final map = <String, ClassPlacement>{};
    for (final c in classes) {
      final sections =
          (await repo
                  .watchSections(schoolId, branchId, yearId, c.classId)
                  .first)
              .where((s) => s.status == ActivationStatus.active);
      map[normName(c.name)] = ClassPlacement(
        c.classId,
        c.name,
        {for (final s in sections) normName(s.name): s.sectionId},
        [for (final s in sections) s.name],
      );
    }
    return PlacementLookup(map);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() {
      _fileName = file.name;
      _csvText = utf8.decode(bytes, allowMalformed: true);
      _parsed = null;
      _rows = const [];
      _results = null;
      _availability.clear();
      _parentEmailInUse.clear();
    });
  }

  /// Inline fix from the review: change the cell(s) in the in-memory sheet
  /// and re-validate exactly like a fresh upload.
  Future<void> _applyEdit(
    BulkCellEdit edit,
    String schoolId,
    String branchId,
  ) async {
    final text = _csvText;
    if (text == null) return;
    AppLogger.debug(
      'Bulk import: inline fix column=${edit.column} '
      'line=${edit.line ?? 'all'} "${edit.oldValue}" -> "${edit.newValue}"',
      tag: 'BulkImport',
    );
    setState(() {
      _csvText = editCsvCells(
        text,
        columnKey: edit.column,
        newValue: edit.newValue,
        line: edit.line,
        oldValue: edit.oldValue,
      );
    });
    await _preview(schoolId, branchId);
  }

  Future<void> _preview(String schoolId, String branchId) async {
    final yearId = _academicYearId;
    final text = _csvText;
    if (yearId == null || text == null) return;
    setState(() {
      _checking = true;
      _progressDone = 0;
      _progressTotal = 0;
    });
    try {
      final placements = await _loadPlacements(schoolId, branchId, yearId);
      final yearName = ref
          .read(academicYearsProvider((schoolId: schoolId, branchId: branchId)))
          .value
          ?.where((y) => y.academicYearId == yearId)
          .map((y) => y.name)
          .firstOrNull;
      final parsed = parseBulkStudentCsv(
        text,
        placements: placements,
        academicYearName: yearName == null
            ? 'the chosen academic year'
            : 'academic year "$yearName"',
      );
      var rows = parsed.rows;
      if (parsed.fileError == null) {
        rows = await _importer().flagExistingAdmissionNumbers(
          schoolId: schoolId,
          branchId: branchId,
          rows: rows,
          cache: _availability,
          onProgress: (d, t) {
            if (!mounted) return;
            setState(() {
              _progressDone = d;
              _progressTotal = t;
            });
          },
        );
        rows = await _importer().flagExistingParentEmails(
          schoolId: schoolId,
          branchId: branchId,
          rows: rows,
          cache: _parentEmailInUse,
        );
      }
      AppLogger.debug(
        'Bulk import: preview rows=${rows.length} '
        'valid=${rows.where((r) => r.isValid).length} fileError=${parsed.fileError}',
        tag: 'BulkImport',
      );
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _rows = rows;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Bulk import: preview failed',
        tag: 'BulkImport',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) context.showSnackBar(userMessageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  BulkStudentImporter _importer() => BulkStudentImporter(
    ref.read(studentRepositoryProvider),
    ref.read(parentRepositoryProvider),
    ref.read(emailLookupProvider),
  );

  Future<void> _runImport(
    String schoolId,
    String branchId,
    String userId,
  ) async {
    final validCount = _rows.where((r) => r.isValid).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import students?'),
        content: Text(
          '$validCount student(s) will be admitted. Rows with errors are '
          'skipped. Admissions cannot be undone in bulk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _importing = true;
      _progressDone = 0;
      _progressTotal = validCount;
    });
    try {
      final results = await _importer().import(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: _academicYearId!,
        createdBy: userId,
        rows: _rows,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _progressDone = d;
            _progressTotal = t;
          });
        },
      );
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ---- fix missing classes / sections from this screen --------------------

  /// What the sheet uses that does not exist yet for the chosen year:
  /// class name -> section names needed in it (new classes), and
  /// class name -> section names to add to a class that already exists.
  ({Map<String, Set<String>> newClasses, Map<String, Set<String>> newSections})
  _missingPlan() {
    final header = _parsed?.header ?? const <String>[];
    final newClasses = <String, Set<String>>{};
    final newSections = <String, Set<String>>{};
    for (final r in _rows) {
      for (final e in r.errors) {
        final cls = _cellOf(header, r.cells, 'class');
        final sec = _cellOf(header, r.cells, 'section');
        if (e.column == 'class' &&
            e.value.trim().isNotEmpty &&
            e.message.startsWith('No class named')) {
          final set = newClasses.putIfAbsent(e.value.trim(), () => <String>{});
          if (sec.isNotEmpty) set.add(sec);
        } else if (e.column == 'section' &&
            e.value.trim().isNotEmpty &&
            cls.isNotEmpty) {
          newSections.putIfAbsent(cls, () => <String>{}).add(e.value.trim());
        }
      }
    }
    return (newClasses: newClasses, newSections: newSections);
  }

  /// Creates the classes (with the sections the sheet needs) and extra
  /// sections, through the same repository calls as Settings → Classes /
  /// Sections, then re-checks the sheet.
  Future<void> _createStructure({
    required String schoolId,
    required String branchId,
    required String userId,
    required Map<String, Set<String>> newClasses,
    required Map<String, Set<String>> newSections,
  }) async {
    final yearId = _academicYearId;
    if (yearId == null) return;
    final repo = ref.read(academicStructureRepositoryProvider);
    var classes = 0, sections = 0;
    final problems = <String>[];
    try {
      final existing = await repo
          .watchClasses(schoolId, branchId, yearId)
          .first;
      var order = existing.isEmpty
          ? 1
          : existing
                    .map((c) => c.displayOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      final idByName = {for (final c in existing) normName(c.name): c.classId};

      Future<void> addSection(String classId, String name) async {
        try {
          await repo.createSection(
            Section(
              sectionId: '',
              schoolId: schoolId,
              branchId: branchId,
              academicYearId: yearId,
              classId: classId,
              name: name,
              status: ActivationStatus.active,
            ),
            createdBy: userId,
          );
          sections++;
        } catch (error, stackTrace) {
          AppLogger.error(
            'Bulk import: could not create section "$name"',
            tag: 'BulkImport',
            error: error,
            stackTrace: stackTrace,
          );
          problems.add('Section "$name": ${userMessageFor(error)}');
        }
      }

      for (final entry in newClasses.entries) {
        try {
          final id = await repo.createClass(
            SchoolClass(
              classId: '',
              schoolId: schoolId,
              branchId: branchId,
              academicYearId: yearId,
              name: entry.key,
              displayOrder: order++,
              status: ActivationStatus.active,
            ),
            createdBy: userId,
          );
          classes++;
          idByName[normName(entry.key)] = id;
          for (final name in entry.value) {
            await addSection(id, name);
          }
        } catch (error, stackTrace) {
          AppLogger.error(
            'Bulk import: could not create class "${entry.key}"',
            tag: 'BulkImport',
            error: error,
            stackTrace: stackTrace,
          );
          problems.add('Class "${entry.key}": ${userMessageFor(error)}');
        }
      }
      for (final entry in newSections.entries) {
        final id = idByName[normName(entry.key)];
        if (id == null) continue;
        for (final name in entry.value) {
          await addSection(id, name);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'Bulk import: creating classes/sections failed',
        tag: 'BulkImport',
        error: error,
        stackTrace: stackTrace,
      );
      problems.add(userMessageFor(error));
    }
    if (mounted) {
      context.showSnackBar(
        problems.isEmpty
            ? 'Created $classes class(es) and $sections section(s).'
            : 'Created $classes class(es), $sections section(s). '
                  'Problems: ${problems.join('; ')}',
        isError: problems.isNotEmpty,
      );
    }
    if (classes + sections > 0 && mounted) {
      await _preview(schoolId, branchId);
    }
  }

  /// Per-problem action: create the missing class (with the sections the
  /// sheet uses in it) or the missing section.
  Widget? _extraAction(
    BulkRowView row,
    BulkCellError e, {
    required bool canCreate,
    required String schoolId,
    required String branchId,
    required String userId,
  }) {
    if (!canCreate || e.value.trim().isEmpty) return null;
    final header = _parsed?.header ?? const <String>[];
    BulkStudentRow? src;
    for (final r in _rows) {
      if (r.line == row.line) src = r;
    }
    if (src == null) return null;
    final cls = _cellOf(header, src.cells, 'class');
    final sec = _cellOf(header, src.cells, 'section');
    if (e.column == 'class' && e.message.startsWith('No class named')) {
      return OutlinedButton.icon(
        onPressed: () => _createStructure(
          schoolId: schoolId,
          branchId: branchId,
          userId: userId,
          newClasses: {
            e.value.trim(): {if (sec.isNotEmpty) sec},
          },
          newSections: const {},
        ),
        icon: const Icon(Icons.add),
        label: Text('Create class "${e.value.trim()}"'),
      );
    }
    if (e.column == 'section' && cls.isNotEmpty) {
      return OutlinedButton.icon(
        onPressed: () => _createStructure(
          schoolId: schoolId,
          branchId: branchId,
          userId: userId,
          newClasses: const {},
          newSections: {
            cls: {e.value.trim()},
          },
        ),
        icon: const Icon(Icons.add),
        label: Text('Create section "${e.value.trim()}" in $cls'),
      );
    }
    return null;
  }

  /// "Create classes / sections" for everything missing in one go.
  Widget? _missingPanel({
    required bool canCreate,
    required bool busy,
    required String schoolId,
    required String branchId,
    required String userId,
  }) {
    if (!canCreate) return null;
    final plan = _missingPlan();
    if (plan.newClasses.isEmpty && plan.newSections.isEmpty) return null;
    final sectionCount =
        plan.newClasses.values.fold<int>(0, (n, s) => n + s.length) +
        plan.newSections.values.fold<int>(0, (n, s) => n + s.length);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not set up for this academic year yet',
              style: theme.textTheme.titleSmall,
            ),
            for (final e in plan.newClasses.entries)
              Text(
                'Class "${e.key}"'
                '${e.value.isEmpty ? '' : ' with section(s): ${e.value.join(', ')}'}',
              ),
            for (final e in plan.newSections.entries)
              Text('Section(s) ${e.value.join(', ')} in class "${e.key}"'),
            const SizedBox(height: AppSpacing.xs),
            FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : () => _createStructure(
                      schoolId: schoolId,
                      branchId: branchId,
                      userId: userId,
                      newClasses: plan.newClasses,
                      newSections: plan.newSections,
                    ),
              icon: const Icon(Icons.add),
              label: Text(
                'Create ${plan.newClasses.length} class(es) and '
                '$sectionCount section(s)',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Created exactly like Settings → Classes / Sections; the sheet '
              'is re-checked straight after.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// "Upload corrected file": pick a file and run the check straight away.
  Future<void> _pickAndCheck(String schoolId, String branchId) async {
    final before = _csvText;
    await _pickFile();
    if (!mounted || _csvText == null || identical(_csvText, before)) return;
    await _preview(schoolId, branchId);
  }

  void _downloadFailed() {
    final parsed = _parsed;
    if (parsed == null) return;
    final failed = <({BulkStudentRow row, String error})>[
      for (final r in _rows.where((r) => !r.isValid))
        (row: r, error: r.errorSummary),
      for (final r in _results ?? const <BulkImportRowResult>[])
        if (r.status == BulkImportStatus.failed)
          (row: r.row, error: r.message ?? 'Import failed'),
    ];
    _saveCsv(
      'students_to_fix.csv',
      bulkStudentErrorsCsv(parsed.header, failed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk student upload')),
      body: AsyncValueWidget(
        value: tenantState,
        data: (tenant) {
          if (tenant?.school == null || tenant?.branch == null) {
            return const EmptyView(
              icon: Icons.upload_file_outlined,
              message: 'No branch found for your account.',
            );
          }
          if (!tenant!.can(Permission.manageStudentData)) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message: 'You do not have permission to admit students.',
            );
          }
          final schoolId = tenant.school!.schoolId;
          final branchId = tenant.branch!.branchId;
          final busy = _checking || _importing;
          final validCount = _rows.where((r) => r.isValid).length;
          final results = _results;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const ActingBranchBanner(verb: 'Importing into'),
              _StepCard(
                number: 1,
                title: 'Download the sample sheet',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _saveCsv(
                        'student_import_template.csv',
                        bulkStudentTemplateCsv(),
                      ),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download sample (CSV)'),
                    ),
                    Text(
                      'Fill one student per row. Up to $bulkStudentMaxRows rows. '
                      'Keep the header row.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _StepCard(
                number: 2,
                title: 'Choose the academic year',
                child: Consumer(
                  builder: (context, ref, _) {
                    final years = ref.watch(
                      academicYearsProvider((
                        schoolId: schoolId,
                        branchId: branchId,
                      )),
                    );
                    return years.when(
                      data: (list) => DropdownButtonFormField<String>(
                        isExpanded: true,
                        value:
                            list.any((y) => y.academicYearId == _academicYearId)
                            ? _academicYearId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Academic year',
                          helperText:
                              'Class and section names in the sheet are matched within this year.',
                        ),
                        items: [
                          for (final y in list)
                            DropdownMenuItem(
                              value: y.academicYearId,
                              child: Text(y.name),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                _academicYearId = v;
                                _parsed = null;
                                _rows = const [];
                                _results = null;
                              }),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) =>
                          const Text('Unable to load academic years.'),
                    );
                  },
                ),
              ),
              _StepCard(
                number: 3,
                title: 'Upload the filled sheet',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_fileName ?? 'Choose CSV file'),
                    ),
                    FilledButton(
                      onPressed:
                          (busy || _csvText == null || _academicYearId == null)
                          ? null
                          : () => _preview(schoolId, branchId),
                      child: const Text('Check file'),
                    ),
                  ],
                ),
              ),
              if (busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _progressTotal == 0
                            ? null
                            : _progressDone / _progressTotal,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _importing
                            ? 'Importing $_progressDone of $_progressTotal…'
                            : 'Checking $_progressDone of $_progressTotal…',
                      ),
                    ],
                  ),
                ),
              if (_parsed?.fileError != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(_parsed!.fileError!),
                  ),
                ),
              if (_parsed != null &&
                  _parsed!.fileError == null &&
                  results == null)
                _PreviewCard(
                  rows: _rows,
                  header: _parsed!.header,
                  validCount: validCount,
                  busy: busy,
                  onImport: () =>
                      _runImport(schoolId, branchId, tenant.user.userId),
                  onDownloadFailed: _downloadFailed,
                  onReupload: () => _pickAndCheck(schoolId, branchId),
                  onEdit: (e) => _applyEdit(e, schoolId, branchId),
                  missingPanel: _missingPanel(
                    canCreate: tenant.can(Permission.manageAcademicSetup),
                    busy: busy,
                    schoolId: schoolId,
                    branchId: branchId,
                    userId: tenant.user.userId,
                  ),
                  extraAction: (row, e) => _extraAction(
                    row,
                    e,
                    canCreate: tenant.can(Permission.manageAcademicSetup),
                    schoolId: schoolId,
                    branchId: branchId,
                    userId: tenant.user.userId,
                  ),
                ),
              if (results != null)
                _ResultCard(
                  rows: _rows,
                  header: _parsed?.header ?? const [],
                  results: results,
                  onDownloadFailed: _downloadFailed,
                  onReupload: () => _pickAndCheck(schoolId, branchId),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final Widget child;
  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$number. $title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

String _cellOf(List<String> header, List<String> cells, String key) {
  final idx = header.indexOf(key);
  return (idx < 0 || idx >= cells.length) ? '' : cells[idx].trim();
}

String _details(List<String> header, BulkStudentRow r) {
  final cls = _cellOf(header, r.cells, 'class');
  final sec = _cellOf(header, r.cells, 'section');
  final parent = [
    _cellOf(header, r.cells, 'parent_first_name'),
    _cellOf(header, r.cells, 'parent_last_name'),
  ].where((e) => e.isNotEmpty).join(' ');
  return [
    if (cls.isNotEmpty || sec.isNotEmpty)
      'Class ${cls.isEmpty ? '?' : cls} · Section ${sec.isEmpty ? '?' : sec}',
    if (parent.isNotEmpty) 'Parent: $parent',
  ].join('   ');
}

class _PreviewCard extends StatelessWidget {
  final List<BulkStudentRow> rows;
  final List<String> header;
  final int validCount;
  final bool busy;
  final VoidCallback onImport;
  final VoidCallback onDownloadFailed;
  final VoidCallback onReupload;
  final BulkCellEditHandler onEdit;
  final Widget? missingPanel;
  final BulkExtraAction? extraAction;
  const _PreviewCard({
    required this.rows,
    required this.header,
    required this.validCount,
    required this.busy,
    required this.onImport,
    required this.onDownloadFailed,
    required this.onReupload,
    required this.onEdit,
    this.missingPanel,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    final invalid = rows.where((r) => !r.isValid).toList();
    return _StepCard(
      number: 4,
      title: 'Review and import',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${rows.length} rows read: $validCount ready, '
            '${invalid.length} need fixing.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (invalid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'To fix: open your sheet, go to the row/cell named in each '
              'problem below, correct it, save the file and choose '
              '"Upload corrected file". Rows without problems can be '
              'imported now; fixed rows can be imported afterwards.',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: (busy || validCount == 0) ? null : onImport,
                icon: const Icon(Icons.playlist_add_check),
                label: Text('Import $validCount ready student(s)'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onReupload,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload corrected file'),
              ),
              if (invalid.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onDownloadFailed,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download rows to fix'),
                ),
            ],
          ),
          if (missingPanel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            missingPanel!,
          ],
          const SizedBox(height: AppSpacing.md),
          BulkRowsView(
            header: header,
            onEdit: onEdit,
            extraAction: extraAction,
            rows: [
              for (final r in rows)
                BulkRowView(
                  line: r.line,
                  who: r.who,
                  details: _details(header, r),
                  errors: r.errors,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final List<BulkStudentRow> rows;
  final List<String> header;
  final List<BulkImportRowResult> results;
  final VoidCallback onDownloadFailed;
  final VoidCallback onReupload;
  const _ResultCard({
    required this.rows,
    required this.header,
    required this.results,
    required this.onDownloadFailed,
    required this.onReupload,
  });

  @override
  Widget build(BuildContext context) {
    final byLine = {for (final r in results) r.row.line: r};
    final notImported = rows.where((r) => byLine[r.line] == null).length;
    final failed = results
        .where((r) => r.status == BulkImportStatus.failed)
        .length;
    final imported = results.length - failed;
    return _StepCard(
      number: 5,
      title: 'Result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$imported student(s) admitted. ${failed + notImported} row(s) '
            'not imported.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (imported > 0)
            const LoginAccessNextStep(
              message:
                  'Students sign in through their parents. Parents were '
                  'imported without a login; select them in the parents list '
                  'and choose "Give login access" — you pick how each first '
                  'password is set.',
              buttonLabel: 'Open parents list',
              route: AppRoutes.parents,
            ),
          if (failed + notImported > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Fix the rows marked "Not imported" in your sheet (keep only '
              'those rows if you like) and upload the corrected file — '
              'already imported students are detected by admission number '
              'and cannot be added twice.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: onReupload,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload corrected file'),
                ),
                OutlinedButton.icon(
                  onPressed: onDownloadFailed,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download rows to fix'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          BulkRowsView(
            header: header,
            rows: [
              for (final r in rows)
                () {
                  final res = byLine[r.line];
                  final BulkRowOutcome outcome;
                  String? message;
                  if (res == null) {
                    outcome = BulkRowOutcome.failed;
                    message = 'Not attempted — fix the problems listed below.';
                  } else if (res.status == BulkImportStatus.failed) {
                    outcome = BulkRowOutcome.failed;
                    message = res.message;
                  } else if (res.status ==
                      BulkImportStatus.importedParentFailed) {
                    outcome = BulkRowOutcome.importedWithWarning;
                    message = res.message;
                  } else {
                    outcome = BulkRowOutcome.imported;
                  }
                  return BulkRowView(
                    line: r.line,
                    who: r.who,
                    details: _details(header, r),
                    errors: r.errors,
                    outcome: outcome,
                    outcomeMessage: message,
                  );
                }(),
            ],
          ),
        ],
      ),
    );
  }
}
