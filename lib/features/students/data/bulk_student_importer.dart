import '../../../core/constants/activation_status.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/bulk_student_import.dart';
import '../domain/parent.dart';
import '../domain/parent_repository.dart';
import '../domain/student.dart';
import '../domain/student_repository.dart';
import '../domain/student_status.dart';

enum BulkImportStatus { imported, importedParentFailed, failed }

class BulkImportRowResult {
  final BulkStudentRow row;
  final BulkImportStatus status;
  final String? message;
  const BulkImportRowResult(this.row, this.status, [this.message]);
}

/// Imports validated sheet rows one at a time through the SAME repository
/// methods the single-admission wizard uses (`admitStudent`,
/// `createParent`, `linkParentToStudent`), so every existing check and every
/// Firestore rule applies unchanged. Each student is its own atomic batch:
/// a failing row never blocks or half-writes another.
class BulkStudentImporter {
  final StudentRepository _students;
  final ParentRepository _parents;

  BulkStudentImporter(this._students, this._parents);

  /// Preview-time check: marks valid rows whose admission number already
  /// exists in the branch. Returns the same rows with extra errors.
  Future<List<BulkStudentRow>> flagExistingAdmissionNumbers({
    required String schoolId,
    required String branchId,
    required List<BulkStudentRow> rows,
    void Function(int done, int total)? onProgress,

    /// admission number -> available?, kept by the caller across re-checks
    /// so an inline fix only queries the numbers it changed.
    Map<String, bool>? cache,
  }) async {
    final out = <BulkStudentRow>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (!r.isValid) {
        out.add(r);
      } else {
        try {
          final number = r.data!.admissionNumber;
          final free =
              cache?[number] ??
              await _students.isAdmissionNumberAvailable(
                schoolId,
                branchId,
                number,
              );
          cache?[number] = free;
          out.add(
            free
                ? r
                : r.withErrors([
                    BulkCellError(
                      column: 'admission_number',
                      label: 'Admission number',
                      value: r.data!.admissionNumber,
                      message:
                          '"${r.data!.admissionNumber}" already belongs to a student in this branch.',
                      fix:
                          'Use a different admission number, or delete this row if the student is already admitted.',
                    ),
                  ]),
          );
        } catch (error, stackTrace) {
          AppLogger.error(
            'Bulk import: admission-number check failed (line ${r.line})',
            tag: 'BulkImport',
            error: error,
            stackTrace: stackTrace,
          );
          out.add(
            r.withErrors([
              BulkCellError(
                column: 'admission_number',
                label: 'Admission number',
                value: r.data!.admissionNumber,
                message: 'could not be checked against existing students.',
                fix:
                    'Check your connection and upload again (${userMessageFor(error)}).',
              ),
            ]),
          );
        }
      }
      onProgress?.call(i + 1, rows.length);
    }
    return out;
  }

  Future<List<BulkImportRowResult>> import({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String createdBy,
    required List<BulkStudentRow> rows,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <BulkImportRowResult>[];
    // parent key (phone digits) -> parentId, so siblings share one record.
    final parentIds = <String, String>{};
    final todo = rows.where((r) => r.isValid).toList();

    AppLogger.debug(
      'Bulk import: start rows=${todo.length} year=$academicYearId',
      tag: 'BulkImport',
    );

    for (var i = 0; i < todo.length; i++) {
      final row = todo[i];
      final d = row.data!;
      String? studentId;
      try {
        studentId = await _students.admitStudent(
          student: Student(
            studentId: '',
            schoolId: schoolId,
            branchId: branchId,
            admissionNumber: d.admissionNumber,
            studentCode: '',
            firstName: d.firstName,
            middleName: d.middleName,
            lastName: d.lastName,
            dateOfBirth: d.dateOfBirth,
            gender: d.gender,
            bloodGroup: d.bloodGroup,
            email: d.email,
            phone: d.phone,
            addressLine1: d.address,
            city: d.city,
            admissionDate: d.admissionDate,
            status: StudentStatus.active,
          ),
          academicYearId: academicYearId,
          classId: d.classId,
          sectionId: d.sectionId,
          rollNumber: d.rollNumber,
          createdBy: createdBy,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Bulk import: admit failed (line ${row.line})',
          tag: 'BulkImport',
          error: error,
          stackTrace: stackTrace,
        );
        results.add(
          BulkImportRowResult(
            row,
            BulkImportStatus.failed,
            userMessageFor(error),
          ),
        );
        onProgress?.call(i + 1, todo.length);
        continue;
      }

      final p = d.parent;
      if (p == null) {
        results.add(BulkImportRowResult(row, BulkImportStatus.imported));
      } else {
        try {
          var parentId = parentIds[p.key];
          if (parentId == null) {
            parentId = await _parents.createParent(
              Parent(
                parentId: '',
                schoolId: schoolId,
                branchId: branchId,
                firstName: p.firstName,
                lastName: p.lastName,
                phone: p.phone,
                email: p.email,
                status: ActivationStatus.active,
              ),
              createdBy: createdBy,
            );
            parentIds[p.key] = parentId;
          }
          await _students.linkParentToStudent(
            schoolId: schoolId,
            branchId: branchId,
            studentId: studentId,
            parentId: parentId,
            relationshipType: p.relationship,
            isPrimary: true,
            isEmergencyContact: true,
            createdBy: createdBy,
          );
          results.add(BulkImportRowResult(row, BulkImportStatus.imported));
        } catch (error, stackTrace) {
          AppLogger.error(
            'Bulk import: parent step failed (line ${row.line}, student $studentId)',
            tag: 'BulkImport',
            error: error,
            stackTrace: stackTrace,
          );
          results.add(
            BulkImportRowResult(
              row,
              BulkImportStatus.importedParentFailed,
              'Student admitted, but the parent could not be saved/linked: '
              '${userMessageFor(error)}. Add the parent from the student profile.',
            ),
          );
        }
      }
      onProgress?.call(i + 1, todo.length);
    }

    AppLogger.debug(
      'Bulk import: done imported=${results.where((r) => r.status != BulkImportStatus.failed).length} '
      'failed=${results.where((r) => r.status == BulkImportStatus.failed).length}',
      tag: 'BulkImport',
    );
    return results;
  }
}
