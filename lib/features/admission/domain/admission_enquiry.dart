import 'admission_status.dart';

/// One parent/guardian on an enquiry. The first is the primary contact.
class EnquiryGuardian {
  final String name;
  final String? relationship;
  final String phone;
  final String? alternatePhone;
  final String? email;
  final bool primary;

  const EnquiryGuardian({
    required this.name,
    required this.phone,
    this.relationship,
    this.alternatePhone,
    this.email,
    this.primary = false,
  });

  factory EnquiryGuardian.fromMap(Map<String, dynamic> m) => EnquiryGuardian(
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    relationship: m['relationship'] as String?,
    alternatePhone: m['alternatePhone'] as String?,
    email: m['email'] as String?,
    primary: m['primary'] == true,
  );

  Map<String, dynamic> toWire() => {
    'name': name,
    'phone': phone,
    'relationship': relationship,
    'alternatePhone': alternatePhone,
    'email': email,
  };
}

/// The editable details of an enquiry — what `createAdmissionEnquiry` and
/// `updateAdmissionEnquiry` accept. Identity (school, branch, number, status,
/// audit) is never sent; the server sets it.
class EnquiryInput {
  final String firstName;
  final String lastName;
  final String? dateOfBirth; // yyyy-mm-dd
  final String? gender; // MALE | FEMALE | OTHER
  final String academicYearId;
  final String interestedClassId;
  final String source;
  final List<EnquiryGuardian> guardians;
  final String? addressLine1;
  final String? city;
  final String? state;
  final String? country;
  final String? previousSchool;
  final String? previousClass;
  final String? specialRequirements;
  final String? remarks;
  final String? nextFollowUpDate; // yyyy-mm-dd
  final String? enquiryDate; // yyyy-mm-dd (create only)

  const EnquiryInput({
    required this.firstName,
    required this.lastName,
    required this.academicYearId,
    required this.interestedClassId,
    required this.source,
    required this.guardians,
    this.dateOfBirth,
    this.gender,
    this.addressLine1,
    this.city,
    this.state,
    this.country,
    this.previousSchool,
    this.previousClass,
    this.specialRequirements,
    this.remarks,
    this.nextFollowUpDate,
    this.enquiryDate,
  });

  Map<String, dynamic> toWire() => {
    'student': {
      'firstName': firstName,
      'lastName': lastName,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
    },
    'academicYearId': academicYearId,
    'interestedClassId': interestedClassId,
    'source': source,
    'guardians': [for (final g in guardians) g.toWire()],
    'address': {
      'line1': addressLine1,
      'city': city,
      'state': state,
      'country': country,
    },
    'previousSchool': previousSchool,
    'previousClass': previousClass,
    'specialRequirements': specialRequirements,
    'remarks': remarks,
    'nextFollowUpDate': nextFollowUpDate,
    'enquiryDate': ?enquiryDate,
  };
}

/// An admission enquiry as read from Firestore.
class AdmissionEnquiry {
  final String id;
  final String schoolId;
  final String branchId;
  final String enquiryNumber;
  final String enquiryDate;
  final String firstName;
  final String lastName;
  final String? dateOfBirth;
  final String? gender;
  final String academicYearId;
  final String interestedClassId;
  final String source;
  final List<EnquiryGuardian> guardians;
  final String? addressLine1;
  final String? city;
  final String? state;
  final String? country;
  final String? previousSchool;
  final String? previousClass;
  final String? specialRequirements;
  final String? remarks;
  final String? assignedTo;
  final AdmissionStatus status;
  final AdmissionStatus? heldFrom;
  final String? statusReason;
  final String? nextFollowUpDate;
  final List<String> duplicateOf;

  /// Follow-up activities: all ever planned, and those still open. While
  /// [activityCount] > 0 the next follow-up date is derived from them.
  final int activityCount;
  final int openActivityCount;

  /// When a follow-up or visit last changed (server time); used to refresh
  /// the timeline, because activity changes do not bump [revision].
  final DateTime? lastActivityAt;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdmissionEnquiry({
    required this.id,
    required this.schoolId,
    required this.branchId,
    required this.enquiryNumber,
    required this.enquiryDate,
    required this.firstName,
    required this.lastName,
    required this.academicYearId,
    required this.interestedClassId,
    required this.source,
    required this.guardians,
    required this.status,
    required this.revision,
    this.dateOfBirth,
    this.gender,
    this.addressLine1,
    this.city,
    this.state,
    this.country,
    this.previousSchool,
    this.previousClass,
    this.specialRequirements,
    this.remarks,
    this.assignedTo,
    this.heldFrom,
    this.statusReason,
    this.nextFollowUpDate,
    this.duplicateOf = const [],
    this.activityCount = 0,
    this.openActivityCount = 0,
    this.lastActivityAt,
    this.createdAt,
    this.updatedAt,
  });

  String get studentName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  EnquiryGuardian? get primaryGuardian =>
      guardians.isEmpty ? null : guardians.first;

  /// [createdAt] / [updatedAt] arrive already converted from Timestamps by the
  /// data layer (this class stays free of Firebase types).
  factory AdmissionEnquiry.fromMap(
    String id,
    Map<String, dynamic> d, {
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastActivityAt,
  }) {
    final student = (d['student'] as Map?)?.cast<String, dynamic>() ?? {};
    final address = (d['address'] as Map?)?.cast<String, dynamic>() ?? {};
    return AdmissionEnquiry(
      id: id,
      schoolId: d['schoolId'] as String? ?? '',
      branchId: d['branchId'] as String? ?? '',
      enquiryNumber: d['enquiryNumber'] as String? ?? '',
      enquiryDate: d['enquiryDate'] as String? ?? '',
      firstName: student['firstName'] as String? ?? '',
      lastName: student['lastName'] as String? ?? '',
      dateOfBirth: student['dateOfBirth'] as String?,
      gender: student['gender'] as String?,
      academicYearId: d['academicYearId'] as String? ?? '',
      interestedClassId: d['interestedClassId'] as String? ?? '',
      source: d['source'] as String? ?? '',
      guardians: [
        for (final g in (d['guardians'] as List? ?? const []))
          if (g is Map) EnquiryGuardian.fromMap(g.cast<String, dynamic>()),
      ],
      addressLine1: address['line1'] as String?,
      city: address['city'] as String?,
      state: address['state'] as String?,
      country: address['country'] as String?,
      previousSchool: d['previousSchool'] as String?,
      previousClass: d['previousClass'] as String?,
      specialRequirements: d['specialRequirements'] as String?,
      remarks: d['remarks'] as String?,
      assignedTo: d['assignedTo'] as String?,
      status:
          AdmissionStatus.tryParse(d['status'] as String?) ??
          AdmissionStatus.newEnquiry,
      heldFrom: AdmissionStatus.tryParse(d['heldFrom'] as String?),
      statusReason: d['statusReason'] as String?,
      nextFollowUpDate: d['nextFollowUpDate'] as String?,
      duplicateOf: [
        for (final x in (d['duplicateOf'] as List? ?? const []))
          if (x is String) x,
      ],
      activityCount: d['activityCount'] is int ? d['activityCount'] as int : 0,
      openActivityCount: d['openActivityCount'] is int
          ? d['openActivityCount'] as int
          : 0,
      revision: d['revision'] is int ? d['revision'] as int : 1,
      lastActivityAt: lastActivityAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// The form's starting values when editing.
  EnquiryInput toInput() => EnquiryInput(
    firstName: firstName,
    lastName: lastName,
    dateOfBirth: dateOfBirth,
    gender: gender,
    academicYearId: academicYearId,
    interestedClassId: interestedClassId,
    source: source,
    guardians: guardians,
    addressLine1: addressLine1,
    city: city,
    state: state,
    country: country,
    previousSchool: previousSchool,
    previousClass: previousClass,
    specialRequirements: specialRequirements,
    remarks: remarks,
    nextFollowUpDate: nextFollowUpDate,
  );
}

/// One immutable line of an enquiry's status history.
class StatusHistoryEntry {
  final int revision;
  final AdmissionStatus? from;
  final AdmissionStatus to;
  final String? reason;
  final String actorId;
  final bool resumed;
  final DateTime? at;

  const StatusHistoryEntry({
    required this.revision,
    required this.to,
    required this.actorId,
    this.from,
    this.reason,
    this.resumed = false,
    this.at,
  });

  factory StatusHistoryEntry.fromMap(Map<String, dynamic> d, {DateTime? at}) =>
      StatusHistoryEntry(
        revision: d['revision'] is int ? d['revision'] as int : 0,
        from: AdmissionStatus.tryParse(d['from'] as String?),
        to:
            AdmissionStatus.tryParse(d['to'] as String?) ??
            AdmissionStatus.newEnquiry,
        reason: d['reason'] as String?,
        actorId: d['actorId'] as String? ?? '',
        resumed: d['resumed'] == true,
        at: at,
      );
}

/// What `createAdmissionEnquiry` returns.
class CreatedEnquiry {
  final String id;
  final String enquiryNumber;
  final List<String> duplicateOf;
  const CreatedEnquiry({
    required this.id,
    required this.enquiryNumber,
    this.duplicateOf = const [],
  });
}
