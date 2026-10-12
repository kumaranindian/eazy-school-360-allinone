import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/file_attachment.dart';
import '../domain/homework_repositories.dart';

/// Uploads and authorised downloads for homework, submissions and
/// announcements.
///
/// Validation here (size, extension, content type derived from the
/// extension — the client's own claim is not trusted) is UX; the Storage
/// rules enforce the same limits and are what protects the bucket. Objects
/// are create-only at unique, tenant- and record-scoped paths. Only the path
/// is stored in Firestore; a download link is minted on demand and works
/// only if the Storage rules allow the caller.
class FirebaseHomeworkFileStore implements HomeworkFileStore {
  final FirebaseStorage _storage;

  FirebaseHomeworkFileStore(this._storage);

  @override
  Future<FileAttachment> upload({
    required String path,
    required String fileName,
    required List<int> bytes,
    required String uploadedBy,
  }) async {
    final problem = FilePolicy.validate(
      fileName: fileName,
      sizeBytes: bytes.length,
    );
    if (problem != null) throw ValidationFailure(problem);
    final contentType = FilePolicy.contentTypeFor(fileName)!;
    try {
      await _storage
          .ref(path)
          .putData(
            Uint8List.fromList(bytes),
            SettableMetadata(contentType: contentType),
          );
      return FileAttachment(
        path: path,
        name: FilePolicy.safeName(fileName),
        contentType: contentType,
        sizeBytes: bytes.length,
        uploadedBy: uploadedBy,
        uploadedAt: DateTime.now(),
      );
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
