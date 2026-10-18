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

  test('LOG-2: debugPrint (printed in release) carries no error bodies', () {
    final call = RegExp(r'debugPrint\(([^;]*?)\);', dotAll: true);
    final body = RegExp(r'\.details|\.message|\$error|\$stackTrace');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('app_logger.dart')) continue; // debug-only itself
      final src = f.readAsStringSync();
      final wholeFileDebugOnly = src.contains('if (!kDebugMode) return;');
      for (final m in call.allMatches(src)) {
        final text = m.group(1)!;
        if (body.hasMatch(text) &&
            !text.contains('kDebugMode') &&
            !wholeFileDebugOnly) {
          offenders.add('${f.path}: ${text.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
