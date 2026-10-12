import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/leave_application.dart';
import '../domain/leave_repositories.dart';
import '../domain/leave_workflow.dart';

class FirebaseLeaveAttachmentStore implements LeaveAttachmentStore {
  final FirebaseStorage _storage;

  FirebaseLeaveAttachmentStore(this._storage);

  static String? contentTypeFor(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
  }

  @override
  Future<LeaveAttachment> upload({
    required String schoolId,
    required String branchId,
    required String applicantUserId,
    required String applicationId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final contentType = contentTypeFor(fileName);
    if (contentType == null ||
        !LeaveWorkflow.attachmentTypes.contains(contentType)) {
      throw const ValidationFailure('Attach a PDF, JPEG or PNG file.');
    }
    if (bytes.isEmpty) {
      throw const ValidationFailure('That file is empty.');
    }
    if (bytes.length >= LeaveWorkflow.maxAttachmentBytes) {
      throw const ValidationFailure('Each file must be under 5 MB.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // A unique prefix: the folder is create-only, so a clash would be refused.
    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path =
        'schools/$schoolId/branches/$branchId/leaveDocs/$applicantUserId/'
        '$applicationId/${unique}_$safe';
    try {
      await _storage
          .ref(path)
          .putData(
            Uint8List.fromList(bytes),
            SettableMetadata(contentType: contentType),
          );
      return LeaveAttachment(
        path: path,
        name: safe,
        contentType: contentType,
        sizeBytes: bytes.length,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> downloadUrl(String storagePath) async {
    try {
      return await _storage.ref(storagePath).getDownloadURL();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
