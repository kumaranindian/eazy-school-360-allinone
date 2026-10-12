import 'dart:io';

import 'package:eazy_school_360/core/config/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the footer version matches pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final value = line.split(':').last.trim(); // 1.0.0+1
    expect(value, '$appVersionName+$appBuildNumber');
  });
}
