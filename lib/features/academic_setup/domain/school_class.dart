import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';

/// A `.../academicYears/{yearId}/classes/{id}` document — e.g. "Class 5".
/// Named `SchoolClass` (not `Class`) purely to avoid confusion with Dart's
/// `class` keyword in prose/reviews; it has no other significance.
///
/// Scoped to a specific academic year on purpose: "Class 5" in 2026-2027
/// and "Class 5" in 2027-2028 are different documents, so each year's
/// roster, sections, and subjects can evolve independently without
/// rewriting history.
class SchoolClass {
  final String classId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String name;
  final String? code;
  final int displayOrder;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const SchoolClass({
    required this.classId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.name,
    this.code,
    required this.displayOrder,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory SchoolClass.fromFirestore(
    String schoolId,
    String branchId,
    String academicYearId,
    String id,
    Map<String, dynamic> data,
  ) {
    return SchoolClass(
      classId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      name: data[FirestoreFields.name] as String? ?? '',
      code: data['code'] as String?,
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
      'displayOrder': displayOrder,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
