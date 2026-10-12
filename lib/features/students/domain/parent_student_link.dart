import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'relationship_type.dart';

/// A `/schools/{s}/branches/{b}/students/{studentId}/parentLinks/{parentId}`
/// document — the many-to-many bridge between [Student] and `Parent`
/// (brief §9). The document id IS the parent id, so "this parent is
/// already linked to this student" is a doc-existence check, not a query
/// — duplicate relationships are prevented by construction.
///
/// Also readable as a Firestore collection-group query
/// (`collectionGroup('parentLinks').where('parentId', '==', ...)`) to
/// answer "which students belong to this parent" without denormalizing
/// student data onto [Parent] — see
/// `docs/milestone-3-student-parent-management.md` → "Querying both
/// directions" and `firestore.indexes.json` for the collection-group
/// index this requires.
class ParentStudentLink {
  final String relationshipId;
  final String schoolId;
  final String branchId;
  final String studentId;
  final String parentId;
  final RelationshipType relationshipType;
  final bool isPrimary;
  final bool isEmergencyContact;
  final bool canAccessPortal;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const ParentStudentLink({
    required this.relationshipId,
    required this.schoolId,
    required this.branchId,
    required this.studentId,
    required this.parentId,
    required this.relationshipType,
    this.isPrimary = false,
    this.isEmergencyContact = false,
    this.canAccessPortal = false,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  ParentStudentLink copyWith({
    RelationshipType? relationshipType,
    bool? isPrimary,
    bool? isEmergencyContact,
    bool? canAccessPortal,
    ActivationStatus? status,
  }) {
    return ParentStudentLink(
      relationshipId: relationshipId,
      schoolId: schoolId,
      branchId: branchId,
      studentId: studentId,
      parentId: parentId,
      relationshipType: relationshipType ?? this.relationshipType,
      isPrimary: isPrimary ?? this.isPrimary,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
      canAccessPortal: canAccessPortal ?? this.canAccessPortal,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory ParentStudentLink.fromFirestore(
    String schoolId,
    String branchId,
    String studentId,
    String parentId,
    Map<String, dynamic> data,
  ) {
    return ParentStudentLink(
      relationshipId: parentId,
      schoolId: schoolId,
      branchId: branchId,
      studentId: studentId,
      parentId: parentId,
      relationshipType: RelationshipType.fromWireValue(
        data['relationshipType'] as String,
      ),
      isPrimary: data['isPrimary'] as bool? ?? false,
      isEmergencyContact: data['isEmergencyContact'] as bool? ?? false,
      canAccessPortal: data['canAccessPortal'] as bool? ?? false,
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
      'studentId': studentId,
      'parentId': parentId,
      ..._editableFields(),
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      ..._editableFields(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  Map<String, dynamic> _editableFields() {
    return {
      'relationshipType': relationshipType.wireValue,
      'isPrimary': isPrimary,
      'isEmergencyContact': isEmergencyContact,
      'canAccessPortal': canAccessPortal,
      FirestoreFields.status: status.wireValue,
    };
  }
}
