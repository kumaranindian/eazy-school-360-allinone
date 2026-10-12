import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'school_status.dart';

/// The `/schools/{schoolId}` document — the tenant root. Every
/// tenant-owned collection traces back to a `schoolId` that must exist
/// here (see FIRESTORE_ARCHITECTURE.md).
class School {
  final String schoolId;
  final String name;
  final String? shortName;
  final String? code;
  final String? logoUrl;
  final String email;
  final String? phone;
  final String? alternatePhone;
  final String? website;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;

  /// The branch shown by default where a single branch must be assumed
  /// (e.g. a future single-branch report). Null until an admin picks one;
  /// never required for tenant isolation itself.
  final String? defaultBranchId;
  final SchoolStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const School({
    required this.schoolId,
    required this.name,
    this.shortName,
    this.code,
    this.logoUrl,
    required this.email,
    this.phone,
    this.alternatePhone,
    this.website,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.defaultBranchId,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  School copyWith({
    String? name,
    String? shortName,
    String? code,
    String? logoUrl,
    String? email,
    String? phone,
    String? alternatePhone,
    String? website,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? defaultBranchId,
  }) {
    return School(
      schoolId: schoolId,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      code: code ?? this.code,
      logoUrl: logoUrl ?? this.logoUrl,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      website: website ?? this.website,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      defaultBranchId: defaultBranchId ?? this.defaultBranchId,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory School.fromFirestore(String schoolId, Map<String, dynamic> data) {
    return School(
      schoolId: schoolId,
      name: data[FirestoreFields.name] as String? ?? '',
      shortName: data['shortName'] as String?,
      code: data['code'] as String?,
      logoUrl: data['logoUrl'] as String?,
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      alternatePhone: data['alternatePhone'] as String?,
      website: data['website'] as String?,
      addressLine1: data['addressLine1'] as String?,
      addressLine2: data['addressLine2'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      postalCode: data['postalCode'] as String?,
      defaultBranchId: data['defaultBranchId'] as String?,
      status: SchoolStatus.fromWireValue(
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
      ..._profileFields(),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Fields a `SCHOOL_ADMIN` is allowed to change — must match exactly
  /// what `firestore.rules`' school-update rule permits via
  /// `diff().affectedKeys().hasOnly([...])`. Deliberately excludes
  /// `status` (a platform-level decision, see SECURITY_ARCHITECTURE.md).
  Map<String, dynamic> toFirestoreProfileUpdate({required String updatedBy}) {
    return {
      ..._profileFields(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  Map<String, dynamic> _profileFields() {
    return {
      FirestoreFields.name: name,
      'shortName': shortName,
      'code': code,
      'logoUrl': logoUrl,
      'email': email,
      'phone': phone,
      'alternatePhone': alternatePhone,
      'website': website,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,
      'defaultBranchId': defaultBranchId,
    };
  }
}
