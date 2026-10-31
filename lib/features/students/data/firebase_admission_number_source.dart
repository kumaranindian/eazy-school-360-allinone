import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/admission_number_format.dart';

/// One ordered, limited range query on `admissionNumber` (single-field index,
/// no composite index needed) over the branch's students. The few highest
/// numbers are read and the ones that are not plain `ADM-<digits>` skipped.
class FirebaseAdmissionNumberSource extends AdmissionNumberSource {
  final FirebaseFirestore _db;
  FirebaseAdmissionNumberSource(this._db);

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
          .collection(FirestoreFields.studentsCollection)
          .where(
            'admissionNumber',
            isGreaterThanOrEqualTo: AdmissionNumberFormat.prefix,
          )
          .where(
            'admissionNumber',
            isLessThan: '${AdmissionNumberFormat.prefix}',
          )
          .orderBy('admissionNumber', descending: true)
          .limit(_window)
          .get();
      return AdmissionNumberFormat.highest([
        for (final d in snap.docs) d.data()['admissionNumber'] as String?,
      ]);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
