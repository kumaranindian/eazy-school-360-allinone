import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../../students/domain/bulk_student_import.dart' show BulkCellError;
import '../domain/bulk_staff_import.dart';
import '../domain/staff.dart';
import '../domain/staff_repository.dart';
import '../domain/staff_status.dart';

enum BulkStaffImportStatus { imported, failed }

class BulkStaffRowResult {
  final BulkStaffRow row;
  final BulkStaffImportStatus status;
  final String? message;
  const BulkStaffRowResult(this.row, this.status, [this.message]);
}

/// Imports validated rows one at a time through `StaffRepository.createStaff`
/// — the same method the "Add staff" form uses, so employee-code
/// reservation, active department/designation checks and every Firestore
/// rule apply unchanged. A failing row never blocks or half-writes another.
class BulkStaffImporter {
  final StaffRepository _staff;

  BulkStaffImporter(this._staff);

  /// Preview-time check: flags valid rows whose employee code is taken.
  Future<List<BulkStaffRow>> flagExistingCodes({
    required String schoolId,
    required String branchId,
    required List<BulkStaffRow> rows,
    void Function(int done, int total)? onProgress,

    /// employee code -> available?, kept by the caller across re-checks.
    Map<String, bool>? cache,
  }) async {
    final out = <BulkStaffRow>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (!r.isValid) {
        out.add(r);
      } else {
        try {
          final code = r.data!.employeeCode;
          final free =
              cache?[code] ??
              await _staff.isEmployeeCodeAvailable(schoolId, branchId, code);
          cache?[code] = free;
          out.add(
            free
                ? r
                : r.withErrors([
                    BulkCellError(
                      column: 'employee_code',
                      label: 'Employee code',
                      value: r.data!.employeeCode,
                      message:
                          '"${r.data!.employeeCode}" already belongs to a staff member in this branch.',
                      fix:
                          'Use a different employee code, or delete this row if the person is already added.',
                    ),
                  ]),
          );
        } catch (error, stackTrace) {
          AppLogger.error(
            'Bulk staff: code check failed (line ${r.line})',
            tag: 'BulkImport',
            error: error,
            stackTrace: stackTrace,
          );
          out.add(
            r.withErrors([
              BulkCellError(
                column: 'employee_code',
                label: 'Employee code',
                value: r.data!.employeeCode,
                message: 'could not be checked against existing staff.',
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

  Future<List<BulkStaffRowResult>> import({
    required String schoolId,
    required String branchId,
    required String createdBy,
    required List<BulkStaffRow> rows,
    void Function(int done, int total)? onProgress,
  }) async {
    final todo = rows.where((r) => r.isValid).toList();
    final results = <BulkStaffRowResult>[];
    AppLogger.debug('Bulk staff: start rows=${todo.length}', tag: 'BulkImport');

    for (var i = 0; i < todo.length; i++) {
      final row = todo[i];
      final d = row.data!;
      try {
        await _staff.createStaff(
          staff: Staff(
            staffId: '',
            schoolId: schoolId,
            branchId: branchId,
            employeeCode: d.employeeCode,
            firstName: d.firstName,
            middleName: d.middleName,
            lastName: d.lastName,
            dateOfBirth: d.dateOfBirth,
            gender: d.gender,
            bloodGroup: d.bloodGroup,
            phone: d.phone,
            alternatePhone: d.alternatePhone,
            email: d.email,
            address: d.address,
            city: d.city,
            state: d.state,
            country: d.country,
            postalCode: d.postalCode,
            joiningDate: d.joiningDate,
            employmentType: d.employmentType,
            departmentId: d.departmentId,
            designationId: d.designationId,
            status: StaffStatus.active,
            isTeacher: d.isTeacher,
          ),
          createdBy: createdBy,
        );
        results.add(BulkStaffRowResult(row, BulkStaffImportStatus.imported));
      } catch (error, stackTrace) {
        AppLogger.error(
          'Bulk staff: create failed (line ${row.line})',
          tag: 'BulkImport',
          error: error,
          stackTrace: stackTrace,
        );
        results.add(
          BulkStaffRowResult(
            row,
            BulkStaffImportStatus.failed,
            userMessageFor(error),
          ),
        );
      }
      onProgress?.call(i + 1, todo.length);
    }
    AppLogger.debug(
      'Bulk staff: done imported=${results.where((r) => r.status == BulkStaffImportStatus.imported).length} '
      'failed=${results.where((r) => r.status == BulkStaffImportStatus.failed).length}',
      tag: 'BulkImport',
    );
    return results;
  }
}
