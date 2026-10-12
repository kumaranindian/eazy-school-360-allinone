import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'academic_record_status.dart';

/// A `/schools/{s}/branches/{b}/students/{studentId}/academicRecords/{id}`
/// document — one per placement (academic year + class + section). This,
/// not [Student]'s current-placement cache, is the source of truth for a
/// student's academic history. A placement change creates a NEW record
/// and marks the previous one [AcademicRecordStatus.completed]/
/// `.transferred`; it is never edited into a different placement in
/// place — see `docs/milestone-3-student-parent-management.md` →
/// "Academic history rule".
class StudentAcademicRecord {
  final String recordId;
  final String studentId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? rollNumber;
  final DateTime startDate;
  final DateTime? endDate;
  final AcademicRecordStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const StudentAcademicRecord({
    required this.recordId,
    required this.studentId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.rollNumber,
    required this.startDate,
    this.endDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory StudentAcademicRecord.fromFirestore(
    String schoolId,
    String branchId,
    String studentId,
    String recordId,
    Map<String, dynamic> data,
  ) {
    return StudentAcademicRecord(
      recordId: recordId,
      studentId: studentId,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: data['academicYearId'] as String,
      classId: data['classId'] as String,
      sectionId: data['sectionId'] as String,
      rollNumber: data['rollNumber'] as String?,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      status: AcademicRecordStatus.fromWireValue(
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
      'studentId': studentId,
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      'classId': classId,
      'sectionId': sectionId,
      'rollNumber': rollNumber,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Closes out this record when the student's placement changes —
  /// [status] becomes `completed`/`transferred`/`withdrawn`, never back
  /// to `active`.
  Map<String, dynamic> toFirestoreClose({
    required AcademicRecordStatus status,
    required DateTime endDate,
    required String updatedBy,
  }) {
    return {
      FirestoreFields.status: status.wireValue,
      'endDate': Timestamp.fromDate(endDate),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
