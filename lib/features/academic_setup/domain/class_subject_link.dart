import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'subject_type.dart';

/// A `.../classes/{classId}/classSubjects/{subjectId}` document — the
/// relationship "this subject is taught in this class." The document id
/// *is* the subject id (not a generated id), so a subject can only be
/// linked to a class once — no separate uniqueness check needed.
///
/// Carries a small denormalized snapshot of the subject (name/code/type)
/// so a class's subject list renders without an N+1 fetch per subject —
/// the full [Subject] document (status, display order, ...) is still the
/// source of truth and is re-read whenever the subject itself is edited.
/// This is a reference, not a duplicate subject document — see
/// FIRESTORE_ARCHITECTURE.md → "Class-subject association".
class ClassSubjectLink {
  final String subjectId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String subjectName;
  final String? subjectCode;
  final SubjectType subjectType;
  final DateTime? createdAt;
  final String? createdBy;

  const ClassSubjectLink({
    required this.subjectId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.subjectName,
    this.subjectCode,
    required this.subjectType,
    this.createdAt,
    this.createdBy,
  });

  factory ClassSubjectLink.fromFirestore(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String subjectId,
    Map<String, dynamic> data,
  ) {
    return ClassSubjectLink(
      subjectId: subjectId,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      classId: classId,
      subjectName: data['subjectName'] as String? ?? '',
      subjectCode: data['subjectCode'] as String?,
      subjectType: SubjectType.fromWireValue(data['subjectType'] as String),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      'classId': classId,
      'subjectName': subjectName,
      'subjectCode': subjectCode,
      'subjectType': subjectType.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
    };
  }
}
