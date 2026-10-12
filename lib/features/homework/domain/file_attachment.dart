import 'package:cloud_firestore/cloud_firestore.dart';

/// Metadata of an uploaded file. The bytes live in Firebase Storage under a
/// tenant- and record-scoped path; only this small record is in Firestore.
/// There is deliberately **no download URL**: access is authorised by the
/// Storage rules for [path] each time, never by a URL a client stored.
class FileAttachment {
  final String path;
  final String name;
  final String contentType;
  final int sizeBytes;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const FileAttachment({
    required this.path,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedBy,
    this.uploadedAt,
  });

  factory FileAttachment.fromMap(Map<String, dynamic> m) => FileAttachment(
    path: m['path'] as String,
    name: m['name'] as String,
    contentType: m['contentType'] as String,
    sizeBytes: (m['sizeBytes'] as num).toInt(),
    uploadedBy: m['uploadedBy'] as String? ?? '',
    uploadedAt: (m['uploadedAt'] as Timestamp?)?.toDate(),
  );

  /// `uploadedAt` is a client timestamp (the file was already uploaded when
  /// this record is written); the object's own server-side creation time in
  /// Storage is the authoritative one.
  Map<String, dynamic> toMap() => {
    'path': path,
    'name': name,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'uploadedBy': uploadedBy,
    'uploadedAt': uploadedAt == null ? null : Timestamp.fromDate(uploadedAt!),
  };
}

/// The upload policy shared by homework, submissions and announcements.
/// `storage.rules` enforces the same limits independently of this class.
abstract final class FilePolicy {
  static const int maxBytes = 10 * 1024 * 1024;
  static const int maxFilesPerRecord = 5;

  static const Map<String, String> typeByExtension = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'txt': 'text/plain',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  static List<String> get extensions => typeByExtension.keys.toList();

  static String? contentTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return typeByExtension[fileName.substring(dot + 1).toLowerCase()];
  }

  /// A user-readable reason the file is not acceptable, or null.
  static String? validate({required String fileName, required int sizeBytes}) {
    if (contentTypeFor(fileName) == null) {
      return 'That file type is not allowed. Use ${extensions.join(', ')}.';
    }
    if (sizeBytes <= 0) return 'That file is empty.';
    // Storage rules require size < 10 MB, so exactly 10 MB is refused too.
    if (sizeBytes >= maxBytes) {
      return 'Each file must be under ${maxBytes ~/ (1024 * 1024)} MB.';
    }
    return null;
  }

  static String safeName(String fileName) =>
      fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
