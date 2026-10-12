import 'package:eazy_school_360/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme builds with light brightness', () {
    expect(AppTheme.light().brightness, Brightness.light);
  });

  test('dark theme builds with dark brightness', () {
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
