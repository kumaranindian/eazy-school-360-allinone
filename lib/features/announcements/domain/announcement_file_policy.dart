import 'dart:math';
import 'dart:typed_data';

import '../../../core/files/file_signatures.dart';

/// The upload policy for announcement attachments. `storage.rules` enforces
/// the type allowlist, the extension and the size cap independently of this
/// class; the checks here give immediate feedback and add what rules cannot:
/// the file's leading bytes must match its extension, so a renamed
/// executable is refused before it is ever uploaded.
abstract final class AnnouncementFilePolicy {
  static const int maxFiles = 10;

  /// Inclusive: a file of exactly this size is accepted (the Storage rule
  /// uses `<=`).
  static const int maxBytes = 10 * 1024 * 1024;

  static const List<String> imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> documentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'txt',
  ];

  static const Map<String, String> typeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
  };

  static List<String> get extensions => typeByExtension.keys.toList();

  static String? extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String? contentTypeFor(String fileName) {
    final ext = extensionOf(fileName);
    return ext == null ? null : typeByExtension[ext];
  }

  static bool isImageType(String contentType) =>
      contentType.startsWith('image/');

  static bool isPdfType(String contentType) => contentType == 'application/pdf';

  /// A user-readable reason the file cannot be attached, or null.
  static String? validate({
    required String fileName,
    required Uint8List bytes,
  }) {
    final ext = extensionOf(fileName);
    if (ext == null || !typeByExtension.containsKey(ext)) {
      return 'That file type is not allowed. Use ${extensions.join(', ')}.';
    }
    if (bytes.isEmpty) return 'That file is empty.';
    if (bytes.length > maxBytes) {
      return 'Each file must be at most ${maxBytes ~/ (1024 * 1024)} MB.';
    }
    if (!signatureMatches(ext, bytes)) {
      return 'The file contents do not match its .$ext type.';
    }
    return null;
  }

  /// Whether adding [adding] files to [current] stays within [maxFiles].
  static String? validateCount({required int current, required int adding}) {
    if (current + adding > maxFiles) {
      final room = max(0, maxFiles - current);
      return 'An announcement can have at most $maxFiles attachments'
          '${room == 0 ? '.' : ' ($room more can be added).'}';
    }
    return null;
  }

  /// Magic-number check: the bytes must look like the claimed format.
  static bool signatureMatches(String ext, Uint8List b) =>
      FileSignatures.matches(ext, b);

  /// The name shown to people: no path separators, control characters or
  /// leading dots, at most 100 characters (the extension is kept).
  static String displayName(String fileName) {
    var n = fileName
        .replaceAll(RegExp(r'[\\/\x00-\x1F\x7F]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (n.isEmpty) n = 'file';
    if (n.length > 100) {
      final ext = extensionOf(n);
      final tail = ext == null ? '' : '.$ext';
      n = n.substring(0, 100 - tail.length) + tail;
    }
    return n;
  }

  /// A fresh, unguessable id. Used for the storage object's name so a
  /// user-chosen filename never reaches a path and two files never collide.
  static String newAttachmentId([Random? random]) {
    final r = random ?? Random.secure();
    final bits = List.generate(
      4,
      (_) => r.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    );
    return 'att_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${bits.join()}';
  }

  /// `<attachmentId>.<ext>` — the last segment of the storage path.
  static String storageFileName(String attachmentId, String fileName) =>
      '$attachmentId.${extensionOf(fileName) ?? 'bin'}';
}
