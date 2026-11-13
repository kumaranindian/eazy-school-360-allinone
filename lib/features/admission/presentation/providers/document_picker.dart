import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/admission_application.dart';

/// A file chosen for upload: its name and bytes.
class PickedDocument {
  final String name;
  final List<int> bytes;
  const PickedDocument(this.name, this.bytes);
}

/// Chooses a document from the device. Behind a provider so tests can pick a
/// file without a platform dialog.
abstract class DocumentPicker {
  /// Null when the person closed the picker.
  Future<PickedDocument?> pick({required bool photoOnly});
}

class FileDocumentPicker implements DocumentPicker {
  const FileDocumentPicker();

  @override
  Future<PickedDocument?> pick({required bool photoOnly}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: photoOnly
          ? const ['jpg', 'jpeg', 'png', 'webp']
          : const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return PickedDocument(file.name, bytes);
  }
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const FileDocumentPicker(),
);

/// Re-exported for the pages that show the limits.
const documentMaxBytes = DocumentLimits.maxBytes;
