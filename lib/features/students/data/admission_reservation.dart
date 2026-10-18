import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../domain/admission_key.dart';

/// The `admissionNumbers/{key}` document that reserves a student's admission
/// number in a branch (ACAD-2). See [AdmissionKey] and the rules for
/// `admissionNumbers`.
class AdmissionReservation {
  const AdmissionReservation._();

  static String path(String schoolId, String branchId, String number) =>
      'schools/$schoolId/branches/$branchId/'
      '${FirestoreFields.admissionNumbersCollection}/${AdmissionKey.of(number)}';

  static Map<String, dynamic> data({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String number,
    required String actorId,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'studentId': studentId,
    'admissionNumber': AdmissionKey.clean(number),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
  };
}
