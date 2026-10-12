import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';

/// A `.../classes/{classId}/sections/{id}` document — e.g. "Class 5 - A".
/// [capacity] is optional and purely informational in this milestone
/// (student allocation isn't built yet); it exists so Student Management
/// has somewhere to read a seat limit from later.
class Section {
  final String sectionId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String name;
  final String? code;
  final int? capacity;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Section({
    required this.sectionId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.name,
    this.code,
    this.capacity,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory Section.fromFirestore(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String id,
    Map<String, dynamic> data,
  ) {
    return Section(
      sectionId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      classId: classId,
      name: data[FirestoreFields.name] as String? ?? '',
      code: data['code'] as String?,
      capacity: (data['capacity'] as num?)?.toInt(),
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
      'classId': classId,
      FirestoreFields.name: name,
      'code': code,
      'capacity': capacity,
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
      'capacity': capacity,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
