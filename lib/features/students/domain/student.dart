import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'blood_group.dart';
import 'gender.dart';
import 'student_status.dart';

/// A `/schools/{schoolId}/branches/{branchId}/students/{studentId}` document.
///
/// This is the student's permanent identity record — admission details,
/// contact/address, and lifecycle [status]. It deliberately is NOT the
/// source of truth for "what class is this student in": `currentClassId`/
/// `currentSectionId`/`currentAcademicYearId`/`currentRollNumber` here are
/// a read-optimization cache only, kept in sync by
/// `StudentRepository.transferStudent`/`enrollStudent` alongside the real
/// source of truth, the `academicRecords` subcollection (one document per
/// placement, never overwritten) — see
/// `docs/milestone-3-student-parent-management.md` → "Why a current-
/// placement cache" for the full reasoning.
class Student {
  final String studentId;
  final String schoolId;
  final String branchId;
  final String admissionNumber;
  final String studentCode;
  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final Gender gender;
  final BloodGroup? bloodGroup;
  final String? photoUrl;
  final String? email;
  final String? phone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final DateTime admissionDate;
  final StudentStatus status;
  final String? statusChangeReason;
  final DateTime? statusChangeDate;
  final String? statusChangeNotes;

  // Current-placement cache — see class doc comment. Null until the
  // student's first academic enrollment is recorded.
  final String? currentAcademicYearId;
  final String? currentClassId;
  final String? currentSectionId;
  final String? currentRollNumber;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Student({
    required this.studentId,
    required this.schoolId,
    required this.branchId,
    required this.admissionNumber,
    required this.studentCode,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    this.bloodGroup,
    this.photoUrl,
    this.email,
    this.phone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.admissionDate,
    required this.status,
    this.statusChangeReason,
    this.statusChangeDate,
    this.statusChangeNotes,
    this.currentAcademicYearId,
    this.currentClassId,
    this.currentSectionId,
    this.currentRollNumber,
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

  /// Roll number as shown beside a name on a register; null if none.
  String? get rollNumberLabel =>
      (currentRollNumber == null || currentRollNumber!.isEmpty)
      ? null
      : currentRollNumber;

  bool get hasCurrentPlacement =>
      currentClassId != null && currentSectionId != null;

  Student copyWith({
    String? admissionNumber,
    String? firstName,
    String? middleName,
    String? lastName,
    DateTime? dateOfBirth,
    Gender? gender,
    BloodGroup? bloodGroup,
    String? photoUrl,
    String? email,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    StudentStatus? status,
    String? statusChangeReason,
    DateTime? statusChangeDate,
    String? statusChangeNotes,
  }) {
    return Student(
      studentId: studentId,
      schoolId: schoolId,
      branchId: branchId,
      admissionNumber: admissionNumber ?? this.admissionNumber,
      studentCode: studentCode,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      admissionDate: admissionDate,
      status: status ?? this.status,
      statusChangeReason: statusChangeReason ?? this.statusChangeReason,
      statusChangeDate: statusChangeDate ?? this.statusChangeDate,
      statusChangeNotes: statusChangeNotes ?? this.statusChangeNotes,
      currentAcademicYearId: currentAcademicYearId,
      currentClassId: currentClassId,
      currentSectionId: currentSectionId,
      currentRollNumber: currentRollNumber,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory Student.fromFirestore(
    String schoolId,
    String branchId,
    String studentId,
    Map<String, dynamic> data,
  ) {
    return Student(
      studentId: studentId,
      schoolId: schoolId,
      branchId: branchId,
      admissionNumber: data['admissionNumber'] as String? ?? '',
      studentCode: data['studentCode'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      middleName: data['middleName'] as String?,
      lastName: data['lastName'] as String? ?? '',
      dateOfBirth: (data['dateOfBirth'] as Timestamp).toDate(),
      gender: Gender.fromWireValue(data['gender'] as String),
      bloodGroup: data['bloodGroup'] == null
          ? null
          : BloodGroup.fromWireValue(data['bloodGroup'] as String),
      photoUrl: data['photoUrl'] as String?,
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      addressLine1: data['addressLine1'] as String?,
      addressLine2: data['addressLine2'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      postalCode: data['postalCode'] as String?,
      admissionDate: (data['admissionDate'] as Timestamp).toDate(),
      status: StudentStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      statusChangeReason: data['statusChangeReason'] as String?,
      statusChangeDate: (data['statusChangeDate'] as Timestamp?)?.toDate(),
      statusChangeNotes: data['statusChangeNotes'] as String?,
      currentAcademicYearId: data['currentAcademicYearId'] as String?,
      currentClassId: data['currentClassId'] as String?,
      currentSectionId: data['currentSectionId'] as String?,
      currentRollNumber: data['currentRollNumber'] as String?,
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
      // A brand-new student has no placement yet — enrollStudent() sets
      // these alongside the first academic record, atomically.
      'currentAcademicYearId': null,
      'currentClassId': null,
      'currentSectionId': null,
      'currentRollNumber': null,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Fields an admin may change on the student's profile — status changes
  /// and placement changes go through their own dedicated methods/rules
  /// paths, not this one. `schoolId`/`branchId`/audit-origin fields are
  /// immutable, enforced by `firestore.rules`.
  Map<String, dynamic> toFirestoreProfileUpdate({required String updatedBy}) {
    return {
      ..._profileFields(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  /// A lifecycle status change (withdrawal, graduation, ...) — see brief
  /// §20. Kept separate from [toFirestoreProfileUpdate] so a profile edit
  /// can never accidentally also change status, and vice versa. Static
  /// because it needs no existing [Student] instance — the repository
  /// applies it directly to the student's document.
  static Map<String, dynamic> firestoreStatusChange({
    required StudentStatus status,
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

  /// Used only by `StudentRepository.enrollStudent`/`transferStudent`
  /// alongside the matching `academicRecords` write, in the same batch —
  /// never called on its own. See the class doc comment.
  Map<String, dynamic> toFirestoreCurrentPlacementUpdate({
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String updatedBy,
  }) {
    return {
      'currentAcademicYearId': academicYearId,
      'currentClassId': classId,
      'currentSectionId': sectionId,
      'currentRollNumber': rollNumber,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  Map<String, dynamic> _profileFields() {
    return {
      'admissionNumber': admissionNumber,
      'studentCode': studentCode,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'displayName': displayName,
      'displayNameLower': displayName.toLowerCase(),
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'gender': gender.wireValue,
      'bloodGroup': bloodGroup?.wireValue,
      'photoUrl': photoUrl,
      'email': email,
      'phone': phone,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,
      'admissionDate': Timestamp.fromDate(admissionDate),
    };
  }
}
