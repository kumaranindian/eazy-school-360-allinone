import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/bulk_import/bulk_rows_view.dart';
import '../../../../shared/error/empty_view.dart';
import '../../data/bulk_staff_importer.dart';
import '../../domain/bulk_staff_import.dart';
import '../../../students/domain/bulk_student_import.dart'
    show BulkCellError, editCsvCells, normName;
import '../../domain/department.dart';
import '../../domain/designation.dart';
import '../../../users/presentation/providers/login_access_providers.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_branch_scope.dart';

/// Bulk staff / teacher upload: download the sample → fill it → upload →
/// review the per-row preview (checked against the branch's real
/// departments, designations and existing employee codes) → import the
/// valid rows. [teachers] makes a blank `is_teacher` cell mean Yes.
class StaffBulkImportPage extends StatelessWidget {
  final bool teachers;
  const StaffBulkImportPage({super.key, this.teachers = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(teachers ? 'Bulk teacher upload' : 'Bulk staff upload'),
      ),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          if (!tenant.can(Permission.manageStaff)) {
            return const EmptyView(
              icon: Icons.lock_outline,
              message: 'You do not have permission to add staff.',
            );
          }
          return _Body(
            schoolId: schoolId,
            branchId: branchId,
            userId: tenant.user.userId,
            teachers: teachers,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String userId;
  final bool teachers;
  const _Body({
    required this.schoolId,
    required this.branchId,
    required this.userId,
    required this.teachers,
  });

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  String? _fileName;
  String? _csvText;
  BulkStaffParseResult? _parsed;
  List<BulkStaffRow> _rows = const [];
  List<BulkStaffRowResult>? _results;
  final Map<String, bool> _codeAvailability = {};
  final Map<String, bool> _emailInUse = {};
  bool _checking = false;
  bool _importing = false;
  int _done = 0;
  int _total = 0;

  BulkStaffImporter get _importer => BulkStaffImporter(
    ref.read(staffRepositoryProvider),
    ref.read(emailLookupProvider),
  );

  Future<void> _save(String fileName, String content) async {
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (mounted && saved != null) context.showSnackBar('Saved $fileName');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Bulk staff: could not save $fileName',
        tag: 'BulkImport',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        context.showSnackBar('Could not save the file.', isError: true);
      }
    }
  }

  Future<void> _pick() async {
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
      _codeAvailability.clear();
      _emailInUse.clear();
    });
  }

  /// Inline fix from the review: change the cell(s) in the in-memory sheet
  /// and re-validate exactly like a fresh upload.
  Future<void> _applyEdit(BulkCellEdit edit) async {
    final text = _csvText;
    if (text == null) return;
    AppLogger.debug(
      'Bulk staff: inline fix column=${edit.column} '
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
    await _check();
  }

  /// Short, valid code derived from a name: "Science & Maths" -> SCIENCE_MATHS.
  String _codeFor(String name) {
    var c = name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (c.length > 20) c = c.substring(0, 20);
    return c.length < 2 ? '${c}_X' : c;
  }

  Future<void> _create(String column, List<String> names) async {
    final repo = ref.read(staffSetupRepositoryProvider);
    var created = 0;
    String? problem;
    for (final name in names) {
      final code = _codeFor(name);
      try {
        if (column == 'department') {
          await repo.createDepartment(
            Department(
              departmentId: Department.idForCode(code),
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              name: name,
              code: code,
              status: ActivationStatus.active,
            ),
            createdBy: widget.userId,
          );
        } else {
          await repo.createDesignation(
            Designation(
              designationId: Designation.idForCode(code),
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              name: name,
              code: code,
              status: ActivationStatus.active,
            ),
            createdBy: widget.userId,
          );
        }
        created++;
        AppLogger.debug(
          'Bulk staff: created $column "$name" (code $code)',
          tag: 'BulkImport',
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Bulk staff: could not create $column "$name"',
          tag: 'BulkImport',
          error: error,
          stackTrace: stackTrace,
        );
        problem = '"$name": ${userMessageFor(error)}';
      }
    }
    if (mounted) {
      context.showSnackBar(
        problem == null
            ? 'Created $created $column(s).'
            : 'Created $created; could not create $problem',
        isError: problem != null,
      );
    }
    if (created > 0) await _check();
  }

  /// Distinct department / designation names in the sheet that do not exist.
  List<String> _missing(String column) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _rows) {
      for (final e in r.errors) {
        if (e.column == column &&
            e.value.trim().isNotEmpty &&
            e.message.startsWith('No $column named') &&
            seen.add(normName(e.value))) {
          out.add(e.value.trim());
        }
      }
    }
    return out;
  }

  Widget? _extraAction(BulkRowView row, BulkCellError e) {
    if ((e.column != 'department' && e.column != 'designation') ||
        e.value.trim().isEmpty ||
        !e.message.startsWith('No ${e.column} named')) {
      return null;
    }
    return OutlinedButton.icon(
      onPressed: () => _create(e.column, [e.value.trim()]),
      icon: const Icon(Icons.add),
      label: Text('Create ${e.column} "${e.value.trim()}"'),
    );
  }

  Future<StaffReferenceLookup> _loadReferences() async {
    // Straight from the repository (not a cached provider) so a department
    // created a moment ago from this screen is included.
    final setup = ref.read(staffSetupRepositoryProvider);
    final departments =
        (await setup.watchDepartments(widget.schoolId, widget.branchId).first)
            .where((d) => d.status == ActivationStatus.active);
    final designations =
        (await setup.watchDesignations(widget.schoolId, widget.branchId).first)
            .where((d) => d.status == ActivationStatus.active);
    return StaffReferenceLookup(
      departmentIds: {
        for (final d in departments) ...{
          normName(d.name): d.departmentId,
          if (d.code.isNotEmpty) normName(d.code): d.departmentId,
        },
      },
      departmentNames: [for (final d in departments) d.name],
      designationIds: {
        for (final d in designations) ...{
          normName(d.name): d.designationId,
          if (d.code.isNotEmpty) normName(d.code): d.designationId,
        },
      },
      designationNames: [for (final d in designations) d.name],
    );
  }

  Future<void> _check() async {
    final text = _csvText;
    if (text == null) return;
    setState(() {
      _checking = true;
      _done = 0;
      _total = 0;
    });
    try {
      final refs = await _loadReferences();
      final parsed = parseBulkStaffCsv(
        text,
        references: refs,
        defaultIsTeacher: widget.teachers,
      );
      var rows = parsed.rows;
      if (parsed.fileError == null) {
        rows = await _importer.flagExistingCodes(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          rows: rows,
          cache: _codeAvailability,
          onProgress: (d, t) {
            if (!mounted) return;
            setState(() {
              _done = d;
              _total = t;
            });
          },
        );
        rows = await _importer.flagExistingEmails(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          rows: rows,
          cache: _emailInUse,
        );
      }
      AppLogger.debug(
        'Bulk staff: preview rows=${rows.length} '
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
        'Bulk staff: preview failed',
        tag: 'BulkImport',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) context.showSnackBar(userMessageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _import() async {
    final valid = _rows.where((r) => r.isValid).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import staff?'),
        content: Text(
          '$valid ${widget.teachers ? 'teacher' : 'staff'} record(s) will be '
          'created. Rows with errors are skipped.',
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
      _done = 0;
      _total = valid;
    });
    try {
      final results = await _importer.import(
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        createdBy: widget.userId,
        rows: _rows,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _done = d;
            _total = t;
          });
        },
      );
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// "Upload corrected file": pick a file and run the check straight away.
  Future<void> _pickAndCheck() async {
    final before = _csvText;
    await _pick();
    if (!mounted || _csvText == null || identical(_csvText, before)) return;
    await _check();
  }

  String _details(List<String> header, BulkStaffRow r) {
    String cell(String key) {
      final idx = header.indexOf(key);
      return (idx < 0 || idx >= r.cells.length) ? '' : r.cells[idx].trim();
    }

    final dept = cell('department');
    final desig = cell('designation');
    final teacher = cell('is_teacher');
    return [
      if (dept.isNotEmpty) 'Department: $dept',
      if (desig.isNotEmpty) 'Designation: $desig',
      if (teacher.isNotEmpty) 'Teacher: $teacher',
    ].join('   ');
  }

  void _downloadFailed() {
    final parsed = _parsed;
    if (parsed == null) return;
    _save(
      'staff_to_fix.csv',
      bulkStaffErrorsCsv(parsed.header, [
        for (final r in _rows.where((r) => !r.isValid))
          (row: r, error: r.errorSummary),
        for (final r in _results ?? const <BulkStaffRowResult>[])
          if (r.status == BulkStaffImportStatus.failed)
            (row: r.row, error: r.message ?? 'Import failed'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _checking || _importing;
    final invalid = _rows.where((r) => !r.isValid).toList();
    final valid = _rows.length - invalid.length;
    final results = _results;
    final failed =
        results
            ?.where((r) => r.status == BulkStaffImportStatus.failed)
            .toList() ??
        const [];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _Step(
          number: 1,
          title: 'Download the sample sheet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: () => _save(
                  widget.teachers
                      ? 'teacher_import_template.csv'
                      : 'staff_import_template.csv',
                  bulkStaffTemplateCsv(teachers: widget.teachers),
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download sample (CSV)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'One person per row, up to $bulkStaffMaxRows rows. Keep the '
                'header row. $bulkStaffHelp',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _Step(
          number: 2,
          title: 'Upload the filled sheet',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : _pick,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_fileName ?? 'Choose CSV file'),
              ),
              FilledButton(
                onPressed: (busy || _csvText == null) ? null : _check,
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
                  value: _total == 0 ? null : _done / _total,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _importing
                      ? 'Importing $_done of $_total…'
                      : 'Checking $_done of $_total…',
                ),
              ],
            ),
          ),
        if (_parsed?.fileError != null)
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(_parsed!.fileError!),
            ),
          ),
        if (_parsed != null && _parsed!.fileError == null && results == null)
          _Step(
            number: 3,
            title: 'Review and import',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_rows.length} rows read: $valid ready, '
                  '${invalid.length} need fixing.',
                  style: theme.textTheme.titleSmall,
                ),
                if (invalid.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'To fix: open your sheet, go to the row/cell named in '
                    'each problem below, correct it, save the file and '
                    'choose "Upload corrected file". Rows without problems '
                    'can be imported now; fixed rows can be imported '
                    'afterwards.',
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: (busy || valid == 0) ? null : _import,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('Import $valid ready record(s)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _pickAndCheck,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Upload corrected file'),
                    ),
                    if (invalid.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _downloadFailed,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download rows to fix'),
                      ),
                  ],
                ),
                if (_missing('department').isNotEmpty ||
                    _missing('designation').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Not set up in this branch yet',
                            style: theme.textTheme.titleSmall,
                          ),
                          if (_missing('department').isNotEmpty)
                            Text(
                              'Departments: ${_missing('department').join(', ')}',
                            ),
                          if (_missing('designation').isNotEmpty)
                            Text(
                              'Designations: ${_missing('designation').join(', ')}',
                            ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (_missing('department').isNotEmpty)
                                FilledButton.tonalIcon(
                                  onPressed: busy
                                      ? null
                                      : () => _create(
                                          'department',
                                          _missing('department'),
                                        ),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    'Create ${_missing('department').length} '
                                    'department(s)',
                                  ),
                                ),
                              if (_missing('designation').isNotEmpty)
                                FilledButton.tonalIcon(
                                  onPressed: busy
                                      ? null
                                      : () => _create(
                                          'designation',
                                          _missing('designation'),
                                        ),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    'Create ${_missing('designation').length} '
                                    'designation(s)',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                BulkRowsView(
                  header: _parsed!.header,
                  onEdit: _applyEdit,
                  extraAction: _extraAction,
                  rows: [
                    for (final r in _rows)
                      BulkRowView(
                        line: r.line,
                        who: r.who,
                        details: _details(_parsed!.header, r),
                        errors: r.errors,
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (results != null)
          _Step(
            number: 4,
            title: 'Result',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${results.length - failed.length} created. '
                  '${failed.length + _rows.where((r) => !r.isValid).length} '
                  'row(s) not imported.',
                  style: theme.textTheme.titleSmall,
                ),
                if (failed.isNotEmpty || _rows.any((r) => !r.isValid)) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Fix the rows marked "Not imported" in your sheet and '
                    'upload the corrected file — employee codes already '
                    'created are detected and cannot be added twice.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _pickAndCheck,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload corrected file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _downloadFailed,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download rows to fix'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                BulkRowsView(
                  header: _parsed?.header ?? const [],
                  rows: [
                    for (final r in _rows)
                      () {
                        final res = results
                            .where((x) => x.row.line == r.line)
                            .firstOrNull;
                        final ok =
                            res?.status == BulkStaffImportStatus.imported;
                        return BulkRowView(
                          line: r.line,
                          who: r.who,
                          details: _details(_parsed?.header ?? const [], r),
                          errors: r.errors,
                          outcome: ok
                              ? BulkRowOutcome.imported
                              : BulkRowOutcome.failed,
                          outcomeMessage: ok
                              ? null
                              : (res?.message ??
                                    'Not attempted — fix the problems '
                                        'listed below.'),
                        );
                      }(),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final Widget child;
  const _Step({required this.number, required this.title, required this.child});

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
