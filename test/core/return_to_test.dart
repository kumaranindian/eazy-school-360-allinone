import 'package:eazy_school_360/core/routing/return_to.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safe', () {
    test('accepts an in-app path with its query', () {
      expect(ReturnTo.safe('/students/abc'), '/students/abc');
      expect(ReturnTo.safe('/fees/invoices?x=1'), '/fees/invoices?x=1');
    });

    test('refuses anything that could leave the app or loop', () {
      for (final bad in [
        null,
        '',
        'students',
        '//evil.example',
        'https://evil.example/',
        '/\\evil.example',
        '/redirect?u=https://evil.example',
        '/login',
        '/create-school',
        '/',
        '/${'a' * 600}',
      ]) {
        expect(ReturnTo.safe(bad), isNull, reason: '$bad');
      }
    });
  });

  group('redirect', () {
    test('remembers the page that was asked for', () {
      expect(
        ReturnTo.redirect('/login', Uri.parse('/students/abc?tab=2')),
        '/login?from=${Uri.encodeQueryComponent('/students/abc?tab=2')}',
      );
    });

    test('a sign-in page asked for directly has nothing to remember', () {
      expect(ReturnTo.redirect('/login', Uri.parse('/register')), '/login');
      expect(ReturnTo.redirect('/', Uri.parse('/login')), '/');
    });

    test('keeps the destination across several redirects, never nests', () {
      final first = ReturnTo.redirect('/', Uri.parse('/students'));
      final second = ReturnTo.redirect('/login', Uri.parse(first));
      expect(Uri.parse(second).path, '/login');
      expect(Uri.parse(second).queryParameters['from'], '/students');
    });

    test('an unsafe destination is dropped', () {
      expect(
        ReturnTo.redirect('/login', Uri.parse('/login?from=//evil.example')),
        '/login',
      );
    });
  });
}
