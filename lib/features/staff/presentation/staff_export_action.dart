import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_mapper.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/bulk_staff_import.dart';
import '../domain/staff.dart';
import 'providers/staff_providers.dart';

/// Upper bound on one export — a branch's staff list, not an unbounded
/// collection read (each page is 200).
const int staffExportMaxRows = 5000;

/// Reads the branch's staff in pages and saves them as a CSV. [teachersOnly]
/// restricts the export to staff flagged as teachers.
Future<void> exportStaffCsv(
  BuildContext context,
  WidgetRef ref, {
  required String schoolId,
  required String branchId,
  required bool teachersOnly,
}) async {
  try {
    context.showSnackBar('Preparing export…');
    final repo = ref.read(staffRepositoryProvider);
    final all = <Staff>[];
    Object? cursor;
    do {
      final page = await repo.fetchStaff(
        schoolId: schoolId,
        branchId: branchId,
        isTeacher: teachersOnly ? true : null,
        pageSize: 200,
        cursor: cursor,
      );
      all.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null && all.length < staffExportMaxRows);

    final departments = await ref.read(
      departmentsProvider((schoolId: schoolId, branchId: branchId)).future,
    );
    final designations = await ref.read(
      designationsProvider((schoolId: schoolId, branchId: branchId)).future,
    );

    final csv = staffExportCsv(
      all,
      departmentNames: {for (final d in departments) d.departmentId: d.name},
      designationNames: {for (final d in designations) d.designationId: d.name},
    );
    final name = teachersOnly ? 'teachers_export.csv' : 'staff_export.csv';
    AppLogger.debug(
      'Staff export: ${all.length} rows -> $name',
      tag: 'BulkExport',
    );
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save $name',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (context.mounted && saved != null) {
      context.showSnackBar(
        'Exported ${all.length} ${teachersOnly ? 'teacher' : 'staff'} record(s).',
      );
    }
  } catch (error, stackTrace) {
    AppLogger.error(
      'Staff export failed',
      tag: 'BulkExport',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      context.showSnackBar(userMessageFor(error), isError: true);
    }
  }
}
