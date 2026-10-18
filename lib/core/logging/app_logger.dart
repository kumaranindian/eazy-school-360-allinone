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
  /// Receives every error-level entry (attached by crash reporting at start-up;
  /// null in tests and debug builds). A failing sink never affects the caller.
  static void Function(String message, Object? error, StackTrace? stackTrace)?
  errorSink;

  /// Build with `--dart-define=AUTH_TRACE=true` to make [trace] print in
  /// release builds (web console, logcat) while diagnosing a sign-in problem.
  /// Leave it off for production builds.
  static const bool _traceBuild = bool.fromEnvironment('AUTH_TRACE');

  /// A diagnostic line that is printed in debug builds and in release builds
  /// made with AUTH_TRACE. Same rules as everything here: never a password,
  /// token or full document; use [maskEmail] for addresses.
  static void trace(String message, {String tag = 'Trace'}) {
    if (!_traceBuild && !kDebugMode) return;
    debugPrint('[TRACE][$tag] $message');
  }

  /// `jo***@example.com` — enough to recognise an account, not to harvest it.
  static String maskEmail(String? email) {
    final e = (email ?? '').trim();
    final at = e.indexOf('@');
    if (at < 1) return e.isEmpty ? '(empty)' : '***';
    final keep = at < 2 ? 1 : 2;
    return '${e.substring(0, keep)}***${e.substring(at)}';
  }

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
    if (level == LogLevel.error) {
      try {
        errorSink?.call(message, error, stackTrace);
      } catch (_) {}
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
