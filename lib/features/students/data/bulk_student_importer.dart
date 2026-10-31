import '../../../core/constants/activation_status.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/admission_number_format.dart';
import '../domain/bulk_student_import.dart';
import '../../users/domain/email_lookup.dart';
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

  final AdmissionNumberSource _numbers;
  final EmailLookup? _emails;

  BulkStudentImporter(
    this._students,
    this._parents,
    this._numbers, [
    this._emails,
  ]);

  /// Preview-time check: a parent email that already belongs to a parent
  /// record is flagged instead of silently creating a second record for the
  /// same login. (Link the existing parent from the student's profile.)
  Future<List<BulkStudentRow>> flagExistingParentEmails({
    required String schoolId,
    required String branchId,
    required List<BulkStudentRow> rows,
    Map<String, bool>? cache,
  }) async {
    final lookup = _emails;
    if (lookup == null) return rows;
    final out = <BulkStudentRow>[];
    for (final r in rows) {
      final email = r.isValid ? r.data!.parent?.email : null;
      if (email == null) {
        out.add(r);
        continue;
      }
      try {
        final used =
            cache?[email] ??
            await lookup.parentEmailInUse(schoolId, branchId, email);
        cache?[email] = used;
        out.add(
          !used
              ? r
              : r.withErrors([
                  BulkCellError(
                    column: 'parent_email',
                    label: 'Parent email',
                    value: email,
                    message:
                        '"$email" already belongs to a parent in this branch.',
                    fix:
                        'Clear the parent columns for this row and link the existing parent from the student profile, or use a different email.',
                  ),
                ]),
        );
      } catch (error) {
        out.add(
          r.withErrors([
            BulkCellError(
              column: 'parent_email',
              label: 'Parent email',
              value: email,
              message: 'could not be checked against existing parents.',
              fix:
                  'Check your connection and upload again (${userMessageFor(error)}).',
            ),
          ]),
        );
      }
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

    // Admission numbers are assigned here, in the same `ADM-0001` series as
    // a single admission: the highest one is read once, then counted up
    // locally. If another admin takes one meanwhile the admission is refused
    // as "already in use" and the count is read again.
    int? last;
    Future<String> nextNumber({bool reread = false}) async {
      if (reread || last == null) {
        last = await _numbers.highestSequence(
          schoolId: schoolId,
          branchId: branchId,
        );
      }
      last = last! + 1;
      return AdmissionNumberFormat.format(last!);
    }

    AppLogger.debug(
      'Bulk import: start rows=${todo.length} year=$academicYearId',
      tag: 'BulkImport',
    );

    for (var i = 0; i < todo.length; i++) {
      final row = todo[i];
      final d = row.data!;
      String? studentId;
      try {
        Future<String> admit(String number) => _students.admitStudent(
          student: Student(
            studentId: '',
            schoolId: schoolId,
            branchId: branchId,
            admissionNumber: number,
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
        for (var attempt = 0; studentId == null; attempt++) {
          try {
            studentId = await admit(await nextNumber(reread: attempt > 0));
          } catch (error) {
            if (attempt >= 2 ||
                !userMessageFor(error).contains('already in use')) {
              rethrow;
            }
          }
        }
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
