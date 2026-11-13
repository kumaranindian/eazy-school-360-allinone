/// The record of an application converted to a student
/// (`functions/admission_conversion.js`, phase 8).
class AdmissionConversion {
  final String studentId;
  final String admissionNumber;
  final List<String> parentIds;
  final int feeNetPaidMinor;
  final int feeBalanceMinor;
  final bool acceptedOutstandingFees;
  final DateTime? convertedAt;

  const AdmissionConversion({
    required this.studentId,
    required this.admissionNumber,
    this.parentIds = const [],
    this.feeNetPaidMinor = 0,
    this.feeBalanceMinor = 0,
    this.acceptedOutstandingFees = false,
    this.convertedAt,
  });

  factory AdmissionConversion.fromMap(
    Map<String, dynamic> d, {
    DateTime? convertedAt,
  }) => AdmissionConversion(
    studentId: d['studentId'] as String? ?? '',
    admissionNumber: d['admissionNumber'] as String? ?? '',
    parentIds: [for (final p in (d['parentIds'] as List? ?? [])) p as String],
    feeNetPaidMinor: (d['feeNetPaidMinor'] as num?)?.toInt() ?? 0,
    feeBalanceMinor: (d['feeBalanceMinor'] as num?)?.toInt() ?? 0,
    acceptedOutstandingFees: d['acceptedOutstandingFees'] == true,
    convertedAt: convertedAt,
  );
}

/// What the admin chooses when converting.
class ConversionInput {
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? rollNumber;
  final String? dateOfBirth;
  final String? gender;
  final bool acceptOutstandingFees;

  const ConversionInput({
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.rollNumber,
    this.dateOfBirth,
    this.gender,
    this.acceptOutstandingFees = false,
  });

  Map<String, dynamic> toWire() => {
    'academicYearId': academicYearId,
    'classId': classId,
    'sectionId': sectionId,
    'rollNumber': ?rollNumber,
    'dateOfBirth': ?dateOfBirth,
    'gender': ?gender,
    'acceptOutstandingFees': acceptOutstandingFees,
  };
}

class ConversionResult {
  final String studentId;
  final String admissionNumber;
  final bool duplicate;
  const ConversionResult({
    required this.studentId,
    required this.admissionNumber,
    required this.duplicate,
  });
}
