import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';

/// A `.../branches/{branchId}/designations/{designationId}` document.
///
/// The document id *is* the lower-cased [code], so a code can exist only
/// once per branch with no separate uniqueness query — Firestore refuses a
/// second `create` on an existing id (see `firestore.rules`). The code is
/// therefore immutable; [name] and [description] stay editable.
///
/// Deactivate with [status], never delete: staff records reference this
/// by id and must keep resolving.
class Designation {
  final String designationId;
  final String schoolId;
  final String branchId;
  final String name;
  final String code;
  final String? description;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Designation({
    required this.designationId,
    required this.schoolId,
    required this.branchId,
    required this.name,
    required this.code,
    this.description,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Letters, digits, `-` and `_`, 2-20 chars. Mirrored in `firestore.rules`.
  static final RegExp codePattern = RegExp(r'^[A-Za-z0-9_-]{2,20}$');

  /// The document id for a code.
  static String idForCode(String code) => code.trim().toLowerCase();

  bool get isActive => status == ActivationStatus.active;

  factory Designation.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return Designation(
      designationId: id,
      schoolId: schoolId,
      branchId: branchId,
      name: data[FirestoreFields.name] as String? ?? '',
      code: data['code'] as String? ?? '',
      description: data['description'] as String?,
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
      FirestoreFields.name: name,
      'code': code.trim(),
      'description': description,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// [code] is deliberately absent — it is the document id.
  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      FirestoreFields.name: name,
      'description': description,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
