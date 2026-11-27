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
    test('accepts common real addresses', () {
      for (final e in [
        'first.last@school.co.in',
        'o\'brien+fees@example.org',
        'a_b-c@sub-domain.example.com',
        '  padded@example.com  ',
      ]) {
        expect(Validators.email(e), isNull, reason: e);
      }
    });
    test('rejects markup, bad dots and bad domains (DEF-04)', () {
      for (final e in [
        '<script>alert(1)</script>@x.com',
        'a b@example.com',
        '.lead@example.com',
        'trail.@example.com',
        'dou..ble@example.com',
        'user@-bad.com',
        'user@example',
        'user@example.c',
        'user@@example.com',
      ]) {
        expect(Validators.email(e), isNotNull, reason: e);
      }
    });
    test('enforces the 64-character local part (DEF-04)', () {
      expect(Validators.email('${'a' * 64}@example.com'), isNull);
      expect(Validators.email('${'a' * 70}@example.com'), isNotNull);
    });
  });

  group('Validators.phone', () {
    test('optional when empty', () => expect(Validators.phone(''), isNull));
    test('accepts usual formats', () {
      for (final p in [
        '+91 98765 43210',
        '044-2345 6789',
        '(04) 123 4567',
        '9876543210',
      ]) {
        expect(Validators.phone(p), isNull, reason: p);
      }
    });
    test('rejects letters and implausible lengths (DEF-03)', () {
      for (final p in [
        'abcde',
        '98765abc10',
        '12345',
        '1234567890123456',
        '98+765 43210',
      ]) {
        expect(Validators.phone(p), isNotNull, reason: p);
      }
    });
  });

  group('Validators.newPassword (OBS-01)', () {
    test('needs 8 characters', () {
      expect(Validators.newPassword('ab12'), isNotNull);
    });
    test('needs a letter and a number', () {
      expect(Validators.newPassword('abcdefgh'), isNotNull);
      expect(Validators.newPassword('12345678'), isNotNull);
    });
    test('accepts a letter-and-number password', () {
      expect(Validators.newPassword('school2026'), isNull);
    });
    test('sign-in still accepts an older letters-only password', () {
      expect(Validators.password('abcdefgh'), isNull);
    });
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

  group('wholeNumber (SET-01-DEF-01: section capacity)', () {
    test('empty is fine when optional, required otherwise', () {
      expect(Validators.wholeNumber(''), isNull);
      expect(Validators.wholeNumber(null), isNull);
      expect(
        Validators.wholeNumber('', required: true, fieldName: 'Capacity'),
        'Capacity is required.',
      );
    });
    test('0 and negatives are refused', () {
      expect(Validators.wholeNumber('0'), 'Enter 1 or more.');
      expect(Validators.wholeNumber('-5'), 'Enter 1 or more.');
    });
    test('decimals and text are refused', () {
      expect(Validators.wholeNumber('2.5'), 'Enter a whole number.');
      expect(Validators.wholeNumber('forty'), 'Enter a whole number.');
    });
    test('a whole number in range is accepted', () {
      expect(Validators.wholeNumber(' 40 '), isNull);
      expect(Validators.wholeNumber('10001'), 'Enter 10000 or less.');
    });
  });
}
