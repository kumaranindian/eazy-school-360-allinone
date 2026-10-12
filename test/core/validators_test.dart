import 'package:eazy_school_360/core/validators/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.email', () {
    test('rejects empty', () => expect(Validators.email(''), isNotNull));
    test(
      'rejects malformed',
      () => expect(Validators.email('not-an-email'), isNotNull),
    );
    test(
      'accepts valid',
      () => expect(Validators.email('user@example.com'), isNull),
    );
  });

  group('Validators.password', () {
    test(
      'rejects short password',
      () => expect(Validators.password('short'), isNotNull),
    );
    test(
      'accepts long enough password',
      () => expect(Validators.password('longenoughpassword'), isNull),
    );
  });

  group('Validators.imageFile', () {
    test('rejects a disallowed extension', () {
      expect(
        Validators.imageFile(fileName: 'logo.gif', sizeBytes: 1000),
        isNotNull,
      );
    });

    test('rejects a file over the size limit', () {
      expect(
        Validators.imageFile(
          fileName: 'logo.png',
          sizeBytes: 3 * 1024 * 1024,
          maxSizeBytes: 2 * 1024 * 1024,
        ),
        isNotNull,
      );
    });

    test('accepts a small png/jpg/jpeg/webp', () {
      for (final name in [
        'logo.png',
        'logo.jpg',
        'logo.jpeg',
        'logo.webp',
        'LOGO.PNG',
      ]) {
        expect(
          Validators.imageFile(fileName: name, sizeBytes: 1000),
          isNull,
          reason: name,
        );
      }
    });
  });
}
