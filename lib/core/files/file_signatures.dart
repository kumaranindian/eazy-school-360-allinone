import 'dart:math';
import 'dart:typed_data';

/// File signatures ("magic numbers"): the leading bytes must match the
/// extension, so a renamed executable or script is refused. Shared by the
/// announcement and homework upload policies; the server repeats the same
/// check on every uploaded file (`functions/upload_check.js`, HW-01-OBS-01).
abstract final class FileSignatures {
  /// Magic-number check: the bytes must look like the claimed format.
  static bool matches(String ext, Uint8List b) {
    bool starts(List<int> sig) =>
        b.length >= sig.length &&
        [for (var i = 0; i < sig.length; i++) b[i] == sig[i]].every((x) => x);
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return starts(const [0xFF, 0xD8, 0xFF]);
      case 'png':
        return starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      case 'webp':
        return b.length >= 12 &&
            starts(const [0x52, 0x49, 0x46, 0x46]) &&
            b[8] == 0x57 &&
            b[9] == 0x45 &&
            b[10] == 0x42 &&
            b[11] == 0x50;
      case 'pdf':
        // The header may be preceded by a little junk, never by much.
        final head = b.length < 1024 ? b : Uint8List.sublistView(b, 0, 1024);
        for (var i = 0; i + 4 <= head.length; i++) {
          if (head[i] == 0x25 &&
              head[i + 1] == 0x50 &&
              head[i + 2] == 0x44 &&
              head[i + 3] == 0x46) {
            return true;
          }
        }
        return false;
      case 'docx':
      case 'xlsx':
        return starts(const [0x50, 0x4B, 0x03, 0x04]);
      case 'doc':
      case 'xls':
        return starts(const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      case 'txt':
        final n = min(b.length, 4096);
        for (var i = 0; i < n; i++) {
          if (b[i] == 0) return false;
        }
        return true;
    }
    return false;
  }
}
