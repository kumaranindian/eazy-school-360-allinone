import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/employee_code_format.dart';

/// One ordered, limited range query on `employeeCode` (single-field index, no
/// composite index needed) over the branch's staff. The few highest codes are
/// read and the ones that are not plain `EMP-<digits>` skipped.
class FirebaseEmployeeCodeSource extends EmployeeCodeSource {
  final FirebaseFirestore _db;
  FirebaseEmployeeCodeSource(this._db);

  static const _window = 50;

  @override
  Future<int> highestSequence({
    required String schoolId,
    required String branchId,
  }) async {
    try {
      final snap = await _db
          .collection(FirestoreFields.schoolsCollection)
          .doc(schoolId)
          .collection(FirestoreFields.branchesCollection)
          .doc(branchId)
          .collection(FirestoreFields.staffCollection)
          .where(
            'employeeCode',
            isGreaterThanOrEqualTo: EmployeeCodeFormat.prefix,
          )
          .where('employeeCode', isLessThan: '${EmployeeCodeFormat.prefix}')
          .orderBy('employeeCode', descending: true)
          .limit(_window)
          .get();
      return EmployeeCodeFormat.highest([
        for (final d in snap.docs) d.data()['employeeCode'] as String?,
      ]);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
