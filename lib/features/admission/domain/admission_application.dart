import 'admission_enquiry.dart';

/// Status of an admission application (`functions/admission_applications.js`).
enum ApplicationStatus {
  draft('DRAFT', 'Draft'),
  submitted('SUBMITTED', 'Submitted'),
  underReview('UNDER_REVIEW', 'Under review'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected'),
  withdrawn('WITHDRAWN', 'Withdrawn');

  final String wire;
  final String label;
  const ApplicationStatus(this.wire, this.label);

  static ApplicationStatus? tryParse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  /// Documents can still be added, verified or removed.
  bool get isOpen => this == draft || this == submitted || this == underReview;

  bool get isFinal => this == rejected || this == withdrawn;
}

enum DocumentStatus {
  uploading('UPLOADING', 'Uploading'),
  uploaded('UPLOADED', 'Awaiting verification'),
  verified('VERIFIED', 'Verified'),
  rejected('REJECTED', 'Rejected'),
  removed('REMOVED', 'Removed'),
  abandoned('ABANDONED', 'Upload failed');

  final String wire;
  final String label;
  const DocumentStatus(this.wire, this.label);

  static DocumentStatus? tryParse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  /// Shown in the document list (removed and abandoned records are history).
  bool get isListed => this == uploaded || this == verified || this == rejected;
}

/// A school-defined document type (settings `customDocumentTypes`).
class CustomDocumentType {
  final String id;
  final String label;
  const CustomDocumentType({required this.id, required this.label});

  Map<String, dynamic> toWire() => {'id': id, 'label': label};

  /// A valid id for [label]: capital letters, digits and underscores, 3-24
  /// long, starting with a letter (what the server accepts).
  static String idFor(String label) {
    var id = label
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (id.isEmpty || !RegExp(r'^[A-Z]').hasMatch(id)) id = 'DOC_$id';
    if (id.length > 24) id = id.substring(0, 24).replaceAll(RegExp(r'_+$'), '');
    while (id.length < 3) {
      id = '${id}X';
    }
    return id;
  }
}

/// The documents every school can ask for (keys mirror the server).
const Map<String, String> builtInDocumentTypes = {
  'BIRTH_CERTIFICATE': 'Birth certificate',
  'STUDENT_PHOTO': 'Student photograph',
  'PARENT_PHOTO': 'Parent photographs',
  'TRANSFER_CERTIFICATE': 'Transfer certificate',
  'PREVIOUS_RECORDS': 'Previous academic records',
  'ADDRESS_PROOF': 'Address proof',
};

/// Photographs must be images; everything else may also be a PDF.
const Set<String> photoDocumentTypes = {'STUDENT_PHOTO', 'PARENT_PHOTO'};

/// The upload limits, checked here for a quick answer and again on the server
/// and in the Storage rules.
abstract final class DocumentLimits {
  static const int maxBytes = 5 * 1024 * 1024;
  static const List<String> imageTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
  ];
  static const List<String> fileTypes = ['application/pdf', ...imageTypes];

  /// Content type for a file name's extension, or null when not allowed.
  static String? contentTypeFor(String fileName, {required bool photo}) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    final type = switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (type == null) return null;
    if (photo && !imageTypes.contains(type)) return null;
    return type;
  }

  /// A reason the file cannot be uploaded, or null.
  static String? problem({
    required String fileName,
    required int sizeBytes,
    required bool photo,
  }) {
    if (sizeBytes <= 0) return 'That file is empty.';
    if (sizeBytes > maxBytes) return 'A file can be at most 5 MB.';
    if (contentTypeFor(fileName, photo: photo) == null) {
      return photo
          ? 'Photographs must be JPEG, PNG or WebP images.'
          : 'Use a PDF, JPEG, PNG or WebP file.';
    }
    return null;
  }
}

/// The application as read from Firestore.
class AdmissionApplication {
  final String id;
  final String schoolId;
  final String branchId;
  final String enquiryId;
  final String enquiryNumber;
  final String applicationNumber;
  final ApplicationStatus status;
  final String firstName;
  final String lastName;
  final String? dateOfBirth;
  final String? gender;
  final String academicYearId;
  final String classId;
  final List<EnquiryGuardian> guardians;
  final String? addressLine1;
  final String? city;
  final String? state;
  final String? country;
  final String? previousSchool;
  final String? previousClass;
  final String? specialRequirements;
  final String? submissionNotes;
  final String? decisionComment;
  final int revision;
  final DateTime? submittedAt;
  final DateTime? decidedAt;

  const AdmissionApplication({
    required this.id,
    required this.schoolId,
    required this.branchId,
    required this.enquiryId,
    required this.enquiryNumber,
    required this.applicationNumber,
    required this.status,
    required this.firstName,
    required this.lastName,
    required this.academicYearId,
    required this.classId,
    required this.guardians,
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
    this.submissionNotes,
    this.decisionComment,
    this.submittedAt,
    this.decidedAt,
  });

  String get studentName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory AdmissionApplication.fromMap(
    String id,
    Map<String, dynamic> d, {
    DateTime? submittedAt,
    DateTime? decidedAt,
  }) {
    final student = (d['student'] as Map?)?.cast<String, dynamic>() ?? {};
    final address = (d['address'] as Map?)?.cast<String, dynamic>() ?? {};
    return AdmissionApplication(
      id: id,
      schoolId: d['schoolId'] as String? ?? '',
      branchId: d['branchId'] as String? ?? '',
      enquiryId: d['enquiryId'] as String? ?? id,
      enquiryNumber: d['enquiryNumber'] as String? ?? '',
      applicationNumber: d['applicationNumber'] as String? ?? '',
      status:
          ApplicationStatus.tryParse(d['status'] as String?) ??
          ApplicationStatus.draft,
      firstName: student['firstName'] as String? ?? '',
      lastName: student['lastName'] as String? ?? '',
      dateOfBirth: student['dateOfBirth'] as String?,
      gender: student['gender'] as String?,
      academicYearId: d['academicYearId'] as String? ?? '',
      classId: d['classId'] as String? ?? '',
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
      submissionNotes: d['submissionNotes'] as String?,
      decisionComment: d['decisionComment'] as String?,
      revision: d['revision'] is int ? d['revision'] as int : 1,
      submittedAt: submittedAt,
      decidedAt: decidedAt,
    );
  }

  /// The edit form's starting values.
  ApplicationInput toInput() => ApplicationInput(
    details: EnquiryInput(
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      gender: gender,
      academicYearId: academicYearId,
      interestedClassId: classId,
      source: '',
      guardians: guardians,
      addressLine1: addressLine1,
      city: city,
      state: state,
      country: country,
      previousSchool: previousSchool,
      previousClass: previousClass,
      specialRequirements: specialRequirements,
    ),
    submissionNotes: submissionNotes,
  );
}

/// What `updateAdmissionApplication` accepts: the same details as an enquiry
/// plus the submission notes. (The server carries the enquiry's source over.)
class ApplicationInput {
  final EnquiryInput details;
  final String? submissionNotes;
  const ApplicationInput({required this.details, this.submissionNotes});

  Map<String, dynamic> toWire() => {
    ...details.toWire(),
    'submissionNotes': submissionNotes,
  };
}

/// One uploaded (or being uploaded) file of an application.
class AdmissionDocument {
  final String id;
  final String type;
  final String label;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String storagePath;
  final DocumentStatus status;
  final String? rejectionReason;
  final String? verifiedBy;
  final int revision;
  final DateTime? uploadedAt;
  final DateTime? verifiedAt;

  const AdmissionDocument({
    required this.id,
    required this.type,
    required this.label,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    required this.status,
    required this.revision,
    this.rejectionReason,
    this.verifiedBy,
    this.uploadedAt,
    this.verifiedAt,
  });

  bool get isImage => DocumentLimits.imageTypes.contains(contentType);
  bool get isPdf => contentType == 'application/pdf';

  factory AdmissionDocument.fromMap(
    String id,
    Map<String, dynamic> d, {
    DateTime? uploadedAt,
    DateTime? verifiedAt,
  }) => AdmissionDocument(
    id: id,
    type: d['type'] as String? ?? '',
    label: d['label'] as String? ?? '',
    fileName: d['fileName'] as String? ?? '',
    contentType: d['contentType'] as String? ?? '',
    sizeBytes: d['sizeBytes'] is int ? d['sizeBytes'] as int : 0,
    storagePath: d['storagePath'] as String? ?? '',
    status:
        DocumentStatus.tryParse(d['status'] as String?) ??
        DocumentStatus.uploading,
    rejectionReason: d['rejectionReason'] as String?,
    verifiedBy: d['verifiedBy'] as String?,
    revision: d['revision'] is int ? d['revision'] as int : 1,
    uploadedAt: uploadedAt,
    verifiedAt: verifiedAt,
  );
}

/// What `requestAdmissionDocumentUpload` returns.
class DocumentUploadIntent {
  final String id;
  final String storagePath;
  const DocumentUploadIntent({required this.id, required this.storagePath});
}

/// One line of an application's history (status changes, comments, documents).
class ApplicationEvent {
  final int revision;
  final String event;
  final ApplicationStatus? from;
  final ApplicationStatus? to;
  final String? comment;
  final String? documentType;
  final String actorId;
  final DateTime? at;

  const ApplicationEvent({
    required this.revision,
    required this.event,
    required this.actorId,
    this.from,
    this.to,
    this.comment,
    this.documentType,
    this.at,
  });

  factory ApplicationEvent.fromMap(Map<String, dynamic> d, {DateTime? at}) =>
      ApplicationEvent(
        revision: d['revision'] is int ? d['revision'] as int : 0,
        event: d['event'] as String? ?? '',
        from: ApplicationStatus.tryParse(d['from'] as String?),
        to: ApplicationStatus.tryParse(d['to'] as String?),
        comment: d['comment'] as String?,
        documentType: d['documentType'] as String?,
        actorId: d['actorId'] as String? ?? '',
        at: at,
      );
}
