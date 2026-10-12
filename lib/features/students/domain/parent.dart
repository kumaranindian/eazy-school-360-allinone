import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';

/// A `/schools/{schoolId}/branches/{branchId}/parents/{parentId}` document.
///
/// Deliberately has no `relationshipType` field — that belongs on
/// [ParentStudentLink], since the same person can be recorded differently
/// per child (see that file's doc comment). Deliberately has no "which
/// students" field either — that's the relationship collection too, never
/// duplicated here (brief §9: "do not simply store student.fatherId...").
class Parent {
  final String parentId;
  final String schoolId;
  final String branchId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String phone;
  final String? alternatePhone;
  final String? email;
  final String? occupation;
  final String? photoUrl;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final ActivationStatus status;

  /// The linked `/users/{uid}` portal account, if one has been granted —
  /// see `docs/milestone-3-student-parent-management.md` → "Parent portal
  /// access foundation". Null means this parent has no login yet; that is
  /// the normal, expected state for most parent records in this milestone.
  final String? linkedUserId;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Parent({
    required this.parentId,
    required this.schoolId,
    required this.branchId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.phone,
    this.alternatePhone,
    this.email,
    this.occupation,
    this.photoUrl,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.status,
    this.linkedUserId,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  String get displayName => [
    firstName,
    if (middleName != null && middleName!.trim().isNotEmpty) middleName,
    lastName,
  ].join(' ');

  bool get hasPortalAccess => linkedUserId != null;

  Parent copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? phone,
    String? alternatePhone,
    String? email,
    String? occupation,
    String? photoUrl,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    ActivationStatus? status,
  }) {
    return Parent(
      parentId: parentId,
      schoolId: schoolId,
      branchId: branchId,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      email: email ?? this.email,
      occupation: occupation ?? this.occupation,
      photoUrl: photoUrl ?? this.photoUrl,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      status: status ?? this.status,
      linkedUserId: linkedUserId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory Parent.fromFirestore(
    String schoolId,
    String branchId,
    String parentId,
    Map<String, dynamic> data,
  ) {
    return Parent(
      parentId: parentId,
      schoolId: schoolId,
      branchId: branchId,
      firstName: data['firstName'] as String? ?? '',
      middleName: data['middleName'] as String?,
      lastName: data['lastName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      alternatePhone: data['alternatePhone'] as String?,
      email: data['email'] as String?,
      occupation: data['occupation'] as String?,
      photoUrl: data['photoUrl'] as String?,
      addressLine1: data['addressLine1'] as String?,
      addressLine2: data['addressLine2'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      postalCode: data['postalCode'] as String?,
      status: ActivationStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      linkedUserId: data['linkedUserId'] as String?,
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
      ..._profileFields(),
      FirestoreFields.status: status.wireValue,
      'linkedUserId': null,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

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
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'displayName': displayName,
      'displayNameLower': displayName.toLowerCase(),
      'phone': phone,
      'alternatePhone': alternatePhone,
      'email': email,
      'occupation': occupation,
      'photoUrl': photoUrl,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,
    };
  }
}
