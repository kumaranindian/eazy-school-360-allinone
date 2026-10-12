import 'package:flutter/material.dart';

/// Small `BuildContext` shortcuts to cut down on `Theme.of(context)...`
/// repetition. Keep this file thin — it's a convenience layer, not a place
/// to grow business logic.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;

  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }
}
