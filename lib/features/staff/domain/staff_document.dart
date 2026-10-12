import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';

enum StaffDocumentType {
  idProof,
  joiningDocument,
  qualificationCertificate,
  other;

  static const Map<StaffDocumentType, String> _wireValues = {
    StaffDocumentType.idProof: 'ID_PROOF',
    StaffDocumentType.joiningDocument: 'JOINING_DOCUMENT',
    StaffDocumentType.qualificationCertificate: 'QUALIFICATION_CERTIFICATE',
    StaffDocumentType.other: 'OTHER',
  };

  static const Map<StaffDocumentType, String> _displayNames = {
    StaffDocumentType.idProof: 'ID proof',
    StaffDocumentType.joiningDocument: 'Joining document',
    StaffDocumentType.qualificationCertificate: 'Qualification certificate',
    StaffDocumentType.other: 'Other',
  };

  String get wireValue => _wireValues[this]!;

  String get displayName => _displayNames[this]!;

  static StaffDocumentType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}

/// Metadata for a file in Firebase Storage — a
/// `.../staff/{staffId}/documents/{documentId}` document. The file bytes
/// are never stored in Firestore, and the download URL isn't stored
/// either: [storagePath] is the reference, and a download URL is requested
/// on demand (which Storage rules authorize) instead of being persisted in
/// Firestore. Removal is soft ([isRemoved]) — Storage rules forbid deletes.
class StaffDocument {
  final String documentId;
  final String schoolId;
  final String branchId;
  final String staffId;
  final StaffDocumentType type;
  final String title;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String storagePath;
  final bool isRemoved;
  final DateTime? createdAt;
  final String? createdBy;

  const StaffDocument({
    required this.documentId,
    required this.schoolId,
    required this.branchId,
    required this.staffId,
    required this.type,
    required this.title,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    this.isRemoved = false,
    this.createdAt,
    this.createdBy,
  });

  /// Types and size accepted for upload; mirrored in `storage.rules`.
  static const Set<String> allowedExtensions = {'pdf', 'jpg', 'jpeg', 'png'};
  static const int maxSizeBytes = 5 * 1024 * 1024;

  static String? validateFile({
    required String fileName,
    required int sizeBytes,
  }) {
    final extension = fileName.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      return 'Please choose a PDF, JPG or PNG file.';
    }
    if (sizeBytes > maxSizeBytes) return 'File must be smaller than 5MB.';
    return null;
  }

  static String contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  factory StaffDocument.fromFirestore(
    String schoolId,
    String branchId,
    String staffId,
    String id,
    Map<String, dynamic> data,
  ) {
    return StaffDocument(
      documentId: id,
      schoolId: schoolId,
      branchId: branchId,
      staffId: staffId,
      type: StaffDocumentType.fromWireValue(data['type'] as String),
      title: data['title'] as String? ?? '',
      fileName: data['fileName'] as String? ?? '',
      contentType: data['contentType'] as String? ?? '',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
      storagePath: data['storagePath'] as String? ?? '',
      isRemoved: data[FirestoreFields.status] == 'REMOVED',
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'staffId': staffId,
      'type': type.wireValue,
      'title': title,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'storagePath': storagePath,
      FirestoreFields.status: 'ACTIVE',
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }
}
