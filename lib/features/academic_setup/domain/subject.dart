import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'subject_type.dart';

/// A `.../academicYears/{yearId}/subjects/{id}` document — the catalog of
/// subjects offered in a given academic year. Which classes actually
/// teach a subject is a separate relationship — see [ClassSubjectLink] —
/// so a subject is never duplicated per class.
class Subject {
  final String subjectId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String name;
  final String? code;
  final String? shortName;
  final SubjectType type;
  final int displayOrder;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Subject({
    required this.subjectId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.name,
    this.code,
    this.shortName,
    required this.type,
    required this.displayOrder,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory Subject.fromFirestore(
    String schoolId,
    String branchId,
    String academicYearId,
    String id,
    Map<String, dynamic> data,
  ) {
    return Subject(
      subjectId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      name: data[FirestoreFields.name] as String? ?? '',
      code: data['code'] as String?,
      shortName: data['shortName'] as String?,
      type: SubjectType.fromWireValue(data['type'] as String),
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
      status: ActivationStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      FirestoreFields.name: name,
      'code': code,
      'shortName': shortName,
      'type': type.wireValue,
      'displayOrder': displayOrder,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      FirestoreFields.name: name,
      'code': code,
      'shortName': shortName,
      'type': type.wireValue,
      'displayOrder': displayOrder,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
