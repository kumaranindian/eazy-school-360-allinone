import 'dart:typed_data';

import 'package:eazy_school_360/features/announcements/domain/announcement_file_uploader.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';

/// In-memory [AnnouncementFileUploader]: records uploads and deletes, never
/// touches Firebase Storage.
class FakeAnnouncementFileUploader implements AnnouncementFileUploader {
  final List<String> uploaded = [];
  final List<String> deleted = [];

  @override
  Future<FileAttachment> upload({
    required String path,
    required String displayName,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    void Function(double progress)? onProgress,
  }) async {
    uploaded.add(path);
    onProgress?.call(1);
    return FileAttachment(
      path: path,
      name: displayName,
      contentType: contentType,
      sizeBytes: bytes.length,
      uploadedBy: uploadedBy,
    );
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);

  @override
  Future<String> downloadUrl(String path) async => 'https://example.test/$path';
}
