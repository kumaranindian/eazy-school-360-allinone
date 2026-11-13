/// What the public enquiry page shows and sends (`functions/admission_public.js`, phase 9).
class PublicClass {
  final String id;
  final String name;
  const PublicClass(this.id, this.name);
}

class PublicYear {
  final String id;
  final String name;
  final List<PublicClass> classes;
  const PublicYear(this.id, this.name, this.classes);
}

class PublicPortalInfo {
  final String schoolName;
  final String branchName;
  final String introText;
  final String consentText;
  final int consentVersion;
  final List<PublicYear> years;
  final bool captchaRequired;

  const PublicPortalInfo({
    required this.schoolName,
    required this.branchName,
    required this.introText,
    required this.consentText,
    required this.consentVersion,
    required this.years,
    this.captchaRequired = false,
  });

  factory PublicPortalInfo.fromMap(Map<String, dynamic> d) => PublicPortalInfo(
    schoolName: d['schoolName'] as String? ?? '',
    branchName: d['branchName'] as String? ?? '',
    introText: d['introText'] as String? ?? '',
    consentText: d['consentText'] as String? ?? '',
    consentVersion: (d['consentVersion'] as num?)?.toInt() ?? 0,
    captchaRequired: d['captchaRequired'] == true,
    years: [
      for (final y in (d['academicYears'] as List? ?? const []))
        if (y is Map)
          PublicYear(y['id'] as String? ?? '', y['name'] as String? ?? '', [
            for (final c in (y['classes'] as List? ?? const []))
              if (c is Map)
                PublicClass(
                  c['id'] as String? ?? '',
                  c['name'] as String? ?? '',
                ),
          ]),
    ],
  );
}

/// What a visitor fills in.
class PublicEnquiryInput {
  final String firstName;
  final String lastName;
  final String? dateOfBirth;
  final String? gender;
  final String academicYearId;
  final String classId;
  final String guardianName;
  final String guardianPhone;
  final String? guardianEmail;
  final String? relationship;

  const PublicEnquiryInput({
    required this.firstName,
    required this.lastName,
    this.dateOfBirth,
    this.gender,
    required this.academicYearId,
    required this.classId,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianEmail,
    this.relationship,
  });

  Map<String, dynamic> toWire() => {
    'student': {
      'firstName': firstName,
      'lastName': lastName,
      'dateOfBirth': ?dateOfBirth,
      'gender': ?gender,
    },
    'academicYearId': academicYearId,
    'interestedClassId': classId,
    'guardians': [
      {
        'name': guardianName,
        'phone': guardianPhone,
        'email': ?guardianEmail,
        'relationship': ?relationship,
      },
    ],
  };
}

abstract class PublicAdmissionRepository {
  Future<PublicPortalInfo> load(String slug);

  /// Returns the reference number shown to the family.
  Future<String> submit({
    required String slug,
    required String requestId,
    required PublicEnquiryInput input,
    required int consentVersion,
    String? captchaToken,
  });
}
