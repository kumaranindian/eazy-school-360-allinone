import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'fee_enums.dart';
import 'money.dart';

/// A `.../studentFeeAssignments/{studentId}__{structureId}` document: "this
/// student is charged this fee head this year", plus any approved concession.
///
/// The deterministic id means a student can hold a fee head only once.
/// Cancelling (status) keeps the record. The assignment stores no amount: the
/// amount is read from the structure **when an invoice is generated** and
/// frozen into that invoice.
class StudentFeeAssignment {
  final String assignmentId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String studentId;
  final String structureId;
  final String structureName;
  final String classId;
  final String? sectionId;
  final ConcessionType concessionType;

  /// Basis points (1% = 100) for [ConcessionType.percent]; minor units for
  /// [ConcessionType.fixed].
  final int concessionValue;
  final String? concessionReason;
  final String? concessionApprovedBy;
  final bool isActive;
  final DateTime? createdAt;
  final String? createdBy;

  const StudentFeeAssignment({
    required this.assignmentId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.studentId,
    required this.structureId,
    required this.structureName,
    required this.classId,
    this.sectionId,
    this.concessionType = ConcessionType.none,
    this.concessionValue = 0,
    this.concessionReason,
    this.concessionApprovedBy,
    this.isActive = true,
    this.createdAt,
    this.createdBy,
  });

  static String idFor(String studentId, String structureId) =>
      '${studentId}__$structureId';

  bool get hasConcession =>
      concessionType != ConcessionType.none && concessionValue > 0;

  /// The concession on one line of [lineAmountMinor], in minor units, never
  /// more than the line itself. Percent concessions use [Money.percentOf]
  /// (half-up).
  int concessionFor(int lineAmountMinor) {
    switch (concessionType) {
      case ConcessionType.none:
        return 0;
      case ConcessionType.percent:
        return Money.percentOf(
          lineAmountMinor,
          concessionValue.clamp(0, 10000),
        );
      case ConcessionType.fixed:
        return concessionValue.clamp(0, lineAmountMinor);
    }
  }

  /// Why this concession is invalid, or null. A concession needs a reason.
  static String? validateConcession(
    ConcessionType type,
    int value,
    String? reason,
  ) {
    if (type == ConcessionType.none) return null;
    if (value <= 0) return 'Enter the concession amount.';
    if (type == ConcessionType.percent && value > 10000) {
      return 'A percentage cannot exceed 100%.';
    }
    if ((reason ?? '').trim().length < 3) {
      return 'Give a reason for the concession.';
    }
    return null;
  }

  factory StudentFeeAssignment.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> d,
  ) {
    return StudentFeeAssignment(
      assignmentId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: d['academicYearId'] as String? ?? '',
      studentId: d['studentId'] as String? ?? '',
      structureId: d['structureId'] as String? ?? '',
      structureName: d['structureName'] as String? ?? '',
      classId: d['classId'] as String? ?? '',
      sectionId: d['sectionId'] as String?,
      concessionType: ConcessionType.fromWireValue(
        d['concessionType'] as String? ?? 'NONE',
      ),
      concessionValue: (d['concessionValue'] as num?)?.toInt() ?? 0,
      concessionReason: d['concessionReason'] as String?,
      concessionApprovedBy: d['concessionApprovedBy'] as String?,
      isActive: d[FirestoreFields.status] == 'ACTIVE',
      createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      createdBy: d[FirestoreFields.createdBy] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'studentId': studentId,
    'structureId': structureId,
    'structureName': structureName,
    'classId': classId,
    'sectionId': sectionId,
    'concessionType': concessionType.wireValue,
    'concessionValue': concessionValue,
    'concessionReason': concessionReason,
    'concessionApprovedBy': hasConcession ? createdBy : null,
    FirestoreFields.status: 'ACTIVE',
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: createdBy,
    FirestoreFields.updatedBy: createdBy,
  };
}
