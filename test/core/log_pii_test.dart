import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LOG-1: `AppLogger.error` reaches Crashlytics (`errorSink`), so a message must
/// not carry an email, phone number or person's name. Log ids instead.
void main() {
  test('no AppLogger.error/warning message interpolates personal data', () {
    final call = RegExp(
      r'AppLogger\.(error|warning)\(([^;]*?)\);',
      dotAll: true,
    );
    final pii = RegExp(
      r'\$\{?[\w.?]*(email|phone|fullName|(student|staff|parent|guardian|teacher|user)\w*\.name)',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        // Only the message argument: stop at the first named argument.
        final message = m
            .group(2)!
            .split(RegExp(r',\s*(tag|error|stackTrace):'))
            .first;
        if (pii.hasMatch(message)) {
          offenders.add('${f.path}: ${message.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
