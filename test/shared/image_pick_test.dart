import 'package:eazy_school_360/shared/media/image_pick.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// A stand-in for the platform picker that records how it was asked.
class _FakePicker extends ImagePickerPlatform {
  XFile? result;
  Object? throwWith;
  ImagePickerOptions? lastOptions;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastOptions = options;
    if (throwWith != null) throw throwWith!;
    return result;
  }
}

/// An [XFile] that really reports [name]: on the VM `XFile.fromData` derives
/// the name from a (non-existent) path, which would make every test look like
/// an extension-less file.
class _NamedFile extends XFile {
  final String _name;
  _NamedFile(this._name, int bytes, {String? mime})
    : super.fromData(Uint8List(bytes), mimeType: mime);

  @override
  String get name => _name;
}

XFile _file(String name, int bytes, {String? mime}) =>
    _NamedFile(name, bytes, mime: mime);

void main() {
  late _FakePicker platform;

  setUp(() {
    platform = _FakePicker();
    ImagePickerPlatform.instance = platform;
  });

  test('asks the picker to scale the image down and compress it', () async {
    platform.result = _file('a.jpg', 1000);
    await pickImageForUpload();
    expect(platform.lastOptions!.maxWidth, uploadImageMaxDimension);
    expect(platform.lastOptions!.maxHeight, uploadImageMaxDimension);
    expect(platform.lastOptions!.imageQuality, lessThan(100));
  });

  test('a normal photo is returned with a normalised extension', () async {
    platform.result = _file('IMG_0042.JPG', 200 * 1024);
    final result = await pickImageForUpload();
    expect(result.image!.extension, 'jpg');
    expect(result.image!.bytes, hasLength(200 * 1024));
    expect(result.error, isNull);
  });

  test('a name with no extension falls back to the MIME type', () async {
    platform.result = _file('blob', 5000, mime: 'image/png');
    expect((await pickImageForUpload()).image!.extension, 'png');
    platform.result = _file('blob', 5000);
    expect((await pickImageForUpload()).image!.extension, 'jpg');
  });

  test('closing the picker is not an error', () async {
    platform.result = null;
    final result = await pickImageForUpload();
    expect(result.image, isNull);
    expect(result.error, isNull);
  });

  test(
    'an image that is still over the limit says so, with its size',
    () async {
      platform.result = _file('big.jpg', 3 * 1024 * 1024);
      final result = await pickImageForUpload();
      expect(result.image, isNull);
      expect(result.error, contains('still too large'));
      expect(result.error, contains('3.0 MB'));
    },
  );

  test('an unsupported type is refused before any upload starts', () async {
    platform.result = _file('anim.gif', 1000);
    final result = await pickImageForUpload();
    expect(result.image, isNull);
    expect(result.error, contains('jpg'));
  });

  test('a denied photo permission is explained', () async {
    platform.throwWith = PlatformException(code: 'photo_access_denied');
    final result = await pickImageForUpload();
    expect(result.error, contains('Allow photo access'));
  });

  test('any other picker failure gives a retry message', () async {
    platform.throwWith = PlatformException(code: 'boom');
    final result = await pickImageForUpload();
    expect(result.error, contains("Couldn't open the photo library"));
  });
}
