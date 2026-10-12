import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'branch_status.dart';

/// A `/schools/{schoolId}/branches/{branchId}` document. A school may have
/// many branches — never assume one school equals one branch.
class Branch {
  final String branchId;
  final String schoolId;
  final String name;
  final String? code;
  final String? email;
  final String? phone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final BranchStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Branch({
    required this.branchId,
    required this.schoolId,
    required this.name,
    this.code,
    this.email,
    this.phone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  Branch copyWith({
    String? name,
    String? code,
    String? email,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    BranchStatus? status,
  }) {
    return Branch(
      branchId: branchId,
      schoolId: schoolId,
      name: name ?? this.name,
      code: code ?? this.code,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory Branch.fromFirestore(
    String schoolId,
    String branchId,
    Map<String, dynamic> data,
  ) {
    return Branch(
      branchId: branchId,
      schoolId: schoolId,
      name: data[FirestoreFields.name] as String? ?? '',
      code: data['code'] as String?,
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      addressLine1: data['addressLine1'] as String?,
      addressLine2: data['addressLine2'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      postalCode: data['postalCode'] as String?,
      status: BranchStatus.fromWireValue(
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
      ..._profileFields(),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Fields an admin may change on an existing branch — `schoolId` and the
  /// audit-origin fields are immutable, enforced by `firestore.rules`.
  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      ..._profileFields(),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  Map<String, dynamic> _profileFields() {
    return {
      FirestoreFields.name: name,
      'code': code,
      'email': email,
      'phone': phone,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,
    };
  }
}
