import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Severity for a log entry. Kept intentionally small — add levels only if
/// a real operational need shows up.
enum LogLevel { debug, warning, error }

/// Centralized application logger.
///
/// Every log call funnels through here so that, in one future change, logs
/// can be shipped to a crash/analytics backend without touching call sites.
///
/// Never log: passwords, auth tokens/session cookies, full user documents,
/// payment details, or any other sensitive personal data. Prefer logging
/// stable identifiers (uid, document id) over raw payloads.
abstract final class AppLogger {
  static void debug(String message, {String? tag}) {
    _log(LogLevel.debug, message, tag: tag);
  }

  static void warning(String message, {String? tag}) {
    _log(LogLevel.warning, message, tag: tag);
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      // `developer.log` only reaches DevTools / some IDE consoles; echo to
      // the plain `flutter run` console so failures are always visible.
      debugPrint(
        '[${level.name.toUpperCase()}][${tag ?? 'EazySchool360'}] $message'
        '${error != null ? '\n  error: ${error.runtimeType}: $error' : ''}',
      );
    }
    developer.log(
      message,
      name: tag ?? 'EazySchool360',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severity(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
