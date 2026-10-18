import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../homework/domain/file_attachment.dart';
import '../domain/announcement_file_policy.dart';
import '../domain/announcement_file_uploader.dart';

/// Firebase Storage implementation. The content type is derived from the
/// file's extension (never the client's claim) and the bytes are checked
/// against it again here; the Storage rules are what actually protect the
/// bucket. Only the path is stored in Firestore.
class FirebaseAnnouncementFileUploader implements AnnouncementFileUploader {
  final FirebaseStorage _storage;

  FirebaseAnnouncementFileUploader(this._storage);

  @override
  Future<FileAttachment> upload({
    required String path,
    required String displayName,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    void Function(double progress)? onProgress,
  }) async {
    final problem = AnnouncementFilePolicy.validate(
      fileName: path,
      bytes: bytes,
    );
    if (problem != null) throw ValidationFailure(problem);
    final type = AnnouncementFilePolicy.contentTypeFor(path)!;
    try {
      final task = _storage
          .ref(path)
          .putData(bytes, SettableMetadata(contentType: type));
      final sub = task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          onProgress?.call(s.bytesTransferred / s.totalBytes);
        }
      });
      try {
        await task;
      } finally {
        await sub.cancel();
      }
      return FileAttachment(
        path: path,
        name: displayName,
        contentType: type,
        sizeBytes: bytes.length,
        uploadedBy: uploadedBy,
        uploadedAt: DateTime.now(),
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> downloadUrl(String path) async {
    try {
      return await _storage.ref(path).getDownloadURL();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
