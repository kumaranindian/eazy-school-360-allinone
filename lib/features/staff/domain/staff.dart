import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../students/domain/blood_group.dart';
import '../../students/domain/gender.dart';
import 'employment_type.dart';
import 'staff_status.dart';

/// A `/schools/{schoolId}/branches/{branchId}/staff/{staffId}` document —
/// the one person record for *everyone* who works at the school: teachers,
/// accountants, drivers, the principal, ...
///
/// Four different identifiers exist; do not conflate them:
/// - [staffId] — the Firestore document id. Opaque, permanent, what every
///   other collection (assignments, future attendance/payroll) references.
/// - [employeeCode] — the human-facing code ("EMP-0001"), typed by an
///   admin, unique per branch, can be corrected (see `staffCodes`).
/// - [userId] — optional link to a `/users/{uid}` application account
///   (== the Firebase Auth uid). Null for staff who never sign in.
/// - the Firebase Auth uid itself, which lives only on `/users`.
///
/// Teaching is a *capability*, not a separate person: [isTeacher] marks a
/// staff member as having teaching responsibility, and what they teach
/// lives in `teacherAssignments` (academic-year aware). There is no
/// teacher document duplicating this one. Likewise [designationId]
/// ("Senior Teacher") is descriptive only and is never an authorization
/// input — the linked `/users` account's role is.
class Staff {
  final String staffId;
  final String schoolId;
  final String branchId;
  final String employeeCode;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? photoUrl;
  final DateTime dateOfBirth;
  final Gender gender;
  final BloodGroup? bloodGroup;
  final String phone;
  final String? alternatePhone;
  final String? email;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final DateTime joiningDate;
  final EmploymentType employmentType;
  final String departmentId;
  final String designationId;
  final StaffStatus status;
  final bool isTeacher;
  final String? userId;
  final String? statusChangeReason;
  final DateTime? statusChangeDate;
  final String? statusChangeNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Staff({
    required this.staffId,
    required this.schoolId,
    required this.branchId,
    required this.employeeCode,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.photoUrl,
    required this.dateOfBirth,
    required this.gender,
    this.bloodGroup,
    required this.phone,
    this.alternatePhone,
    this.email,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.joiningDate,
    required this.employmentType,
    required this.departmentId,
    required this.designationId,
    required this.status,
    this.isTeacher = false,
    this.userId,
    this.statusChangeReason,
    this.statusChangeDate,
    this.statusChangeNotes,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  String get displayName => computeDisplayName(firstName, middleName, lastName);

  static String computeDisplayName(
    String firstName,
    String? middleName,
    String lastName,
  ) {
    return [
      firstName,
      if (middleName != null && middleName.trim().isNotEmpty) middleName,
      lastName,
    ].join(' ');
  }

  /// The form in which a code is compared and reserved: case-insensitive,
  /// so "emp-0001" and "EMP-0001" cannot both exist. Also the document id
  /// of the code's `staffCodes` reservation.
  static String normalizeEmployeeCode(String code) => code.trim().toLowerCase();

  /// Letters, digits, `-` and `_`, 2-20 chars — keeps the code safe to use
  /// as a Firestore document id. Mirrored in `firestore.rules`.
  static final RegExp employeeCodePattern = RegExp(r'^[A-Za-z0-9_-]{2,20}$');

  bool get canReceiveAssignments => status.canReceiveAssignments && isTeacher;

  Staff copyWith({
    String? employeeCode,
    String? firstName,
    String? middleName,
    String? lastName,
    DateTime? dateOfBirth,
    Gender? gender,
    BloodGroup? bloodGroup,
    String? phone,
    String? alternatePhone,
    String? email,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    DateTime? joiningDate,
    EmploymentType? employmentType,
    String? departmentId,
    String? designationId,
    StaffStatus? status,
    bool? isTeacher,
  }) {
    return Staff(
      staffId: staffId,
      schoolId: schoolId,
      branchId: branchId,
      employeeCode: employeeCode ?? this.employeeCode,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      photoUrl: photoUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      email: email ?? this.email,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      joiningDate: joiningDate ?? this.joiningDate,
      employmentType: employmentType ?? this.employmentType,
      departmentId: departmentId ?? this.departmentId,
      designationId: designationId ?? this.designationId,
      status: status ?? this.status,
      isTeacher: isTeacher ?? this.isTeacher,
      userId: userId,
      statusChangeReason: statusChangeReason,
      statusChangeDate: statusChangeDate,
      statusChangeNotes: statusChangeNotes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory Staff.fromFirestore(
    String schoolId,
    String branchId,
    String staffId,
    Map<String, dynamic> data,
  ) {
    return Staff(
      staffId: staffId,
      schoolId: schoolId,
      branchId: branchId,
      employeeCode: data['employeeCode'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      middleName: data['middleName'] as String?,
      lastName: data['lastName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      dateOfBirth: (data['dateOfBirth'] as Timestamp).toDate(),
      gender: Gender.fromWireValue(data['gender'] as String),
      bloodGroup: data['bloodGroup'] == null
          ? null
          : BloodGroup.fromWireValue(data['bloodGroup'] as String),
      phone: data['phone'] as String? ?? '',
      alternatePhone: data['alternatePhone'] as String?,
      email: data['email'] as String?,
      address: data['address'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      postalCode: data['postalCode'] as String?,
      joiningDate: (data['joiningDate'] as Timestamp).toDate(),
      employmentType: EmploymentType.fromWireValue(
        data['employmentType'] as String,
      ),
      departmentId: data['departmentId'] as String? ?? '',
      designationId: data['designationId'] as String? ?? '',
      status: StaffStatus.fromWireValue(data[FirestoreFields.status] as String),
      isTeacher: data['isTeacher'] as bool? ?? false,
      userId: data['userId'] as String?,
      statusChangeReason: data['statusChangeReason'] as String?,
      statusChangeDate: (data['statusChangeDate'] as Timestamp?)?.toDate(),
      statusChangeNotes: data['statusChangeNotes'] as String?,
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  /// New staff always start ACTIVE with no account link — [status] and
  /// [userId] on the instance are ignored here by design; linking a user
  /// and changing status have their own paths.
  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      ..._profileFields(),
      'photoUrl': null,
      'userId': null,
      FirestoreFields.status: StaffStatus.active.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Profile edit. Excludes status, photo, and the account link — each has
  /// its own method so an edit form can never overwrite them with a stale
  /// value. `schoolId`/`branchId`/audit-origin fields are immutable
  /// (enforced by `firestore.rules`).
  Map<String, dynamic> toFirestoreProfileUpdate({required String updatedBy}) {
    return {
      ..._profileFields(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  static Map<String, dynamic> firestoreStatusChange({
    required StaffStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  }) {
    return {
      FirestoreFields.status: status.wireValue,
      'statusChangeReason': reason,
      'statusChangeDate': Timestamp.fromDate(effectiveDate),
      'statusChangeNotes': notes,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  Map<String, dynamic> _profileFields() {
    return {
      'employeeCode': employeeCode.trim(),
      'employeeCodeLower': normalizeEmployeeCode(employeeCode),
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'displayName': displayName,
      'displayNameLower': displayName.toLowerCase(),
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'gender': gender.wireValue,
      'bloodGroup': bloodGroup?.wireValue,
      'phone': phone,
      'alternatePhone': alternatePhone,
      'email': email,
      'emailLower': email?.toLowerCase(),
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,
      'joiningDate': Timestamp.fromDate(joiningDate),
      'employmentType': employmentType.wireValue,
      'departmentId': departmentId,
      'designationId': designationId,
      'isTeacher': isTeacher,
    };
  }
}
