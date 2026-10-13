import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/validators/validators.dart';

/// An image chosen for upload: its bytes and a normalised file extension.
class PickedImage {
  final List<int> bytes;
  final String extension;

  const PickedImage(this.bytes, this.extension);
}

/// Why [pickImageForUpload] returned nothing, in words for the user. A user who
/// simply closed the picker is not an error, so that case returns null with no
/// message.
class ImagePickResult {
  final PickedImage? image;
  final String? error;

  const ImagePickResult.picked(PickedImage this.image) : error = null;
  const ImagePickResult.failed(String this.error) : image = null;
  const ImagePickResult.cancelled() : image = null, error = null;
}

/// Largest side, in pixels, of a profile photo or logo. Anything bigger is
/// scaled down while picking: a phone photo is typically 3-8 MB, which the
/// 2 MB storage limit would refuse, and a 1024px picture is plenty for an
/// avatar or a logo.
const int uploadImageMaxDimension = 1024;

const _allowed = {'jpg', 'jpeg', 'png', 'webp'};

/// Picks an image from the gallery, scales it down, and checks it against the
/// storage rules' limits (type and 2 MB) so a bad file is explained
/// immediately instead of failing after a long upload.
Future<ImagePickResult> pickImageForUpload({
  ImagePicker? picker,
  int maxBytes = 2 * 1024 * 1024,
}) async {
  final XFile? picked;
  try {
    picked = await (picker ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
      maxWidth: uploadImageMaxDimension.toDouble(),
      maxHeight: uploadImageMaxDimension.toDouble(),
      imageQuality: 85,
    );
  } on PlatformException catch (error) {
    final denied =
        error.code.contains('denied') || error.code.contains('permission');
    return ImagePickResult.failed(
      denied
          ? 'Allow photo access in your device settings to choose a picture.'
          : "Couldn't open the photo library. Please try again.",
    );
  }
  if (picked == null) return const ImagePickResult.cancelled();

  final bytes = await picked.readAsBytes();
  final extension = _extensionOf(picked);
  final problem = Validators.imageFile(
    fileName: 'image.$extension',
    sizeBytes: bytes.length,
    maxSizeBytes: maxBytes,
    allowedExtensions: _allowed,
  );
  if (problem != null) {
    final tooBig = bytes.length > maxBytes;
    return ImagePickResult.failed(
      tooBig
          ? 'That image is still too large after resizing '
                '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). '
                'Please choose a smaller one.'
          : problem,
    );
  }
  return ImagePickResult.picked(PickedImage(bytes, extension));
}

/// The extension from the file name, or, when the name has none (a camera
/// capture or a browser blob), from the MIME type; never an unsupported one.
String _extensionOf(XFile file) {
  final name = file.name;
  final dot = name.lastIndexOf('.');
  if (dot >= 0 && dot < name.length - 1) {
    final fromName = name.substring(dot + 1).toLowerCase();
    if (_allowed.contains(fromName)) return fromName;
    // A name that looks like it has an extension we do not accept: report it.
    if (fromName.length <= 5) return fromName;
  }
  return switch (file.mimeType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
}
