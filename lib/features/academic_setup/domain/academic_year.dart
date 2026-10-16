import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'academic_year_status.dart';

/// A `/schools/{schoolId}/branches/{branchId}/academicYears/{id}` document,
/// e.g. "2026-2027". Classes, sections, subjects, and holidays all nest
/// under a specific academic year — see FIRESTORE_ARCHITECTURE.md.
class AcademicYear {
  final String academicYearId;
  final String schoolId;
  final String branchId;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final AcademicYearStatus status;

  /// The school-wide year (`/schools/{s}/academicYears/{id}`) this branch year
  /// was opened from; its id equals this document's id. Null for older
  /// branch-only years. A linked year keeps the school's name and dates.
  final String? schoolYearId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const AcademicYear({
    required this.academicYearId,
    required this.schoolId,
    required this.branchId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.schoolYearId,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory AcademicYear.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return AcademicYear(
      academicYearId: id,
      schoolId: schoolId,
      branchId: branchId,
      name: data[FirestoreFields.name] as String? ?? '',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      status: AcademicYearStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      schoolYearId: data['schoolYearId'] as String?,
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
      FirestoreFields.name: name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      FirestoreFields.status: status.wireValue,
      'schoolYearId': ?schoolYearId,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      FirestoreFields.name: name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
