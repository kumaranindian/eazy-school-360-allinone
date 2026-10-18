import 'dart:typed_data';

import '../../homework/domain/file_attachment.dart';

/// Uploads, deletes and mints authorised download links for announcement
/// attachments. Nothing here stores a URL: a link is minted on demand and
/// works only if the Storage rules allow the caller.
abstract class AnnouncementFileUploader {
  /// Uploads [bytes] to [path]. [onProgress] receives 0..1.
  Future<FileAttachment> upload({
    required String path,
    required String displayName,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    void Function(double progress)? onProgress,
  });

  Future<void> delete(String path);

  Future<String> downloadUrl(String path);
}
