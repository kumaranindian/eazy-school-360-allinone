import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../logging/app_logger.dart';

/// Whether App Check should be activated, and with which web key.
///
/// App Check is opt-in per build (`--dart-define=APP_CHECK_ENABLED=true`, plus
/// `APP_CHECK_WEB_KEY=<reCAPTCHA v3 site key>` for web). The functions side
/// only rejects unattested callers when `ENFORCE_APP_CHECK=true`, so a build
/// can send tokens long before enforcement is switched on
/// (docs/app-check-and-monitoring.md).
enum AppCheckPlan { off, missingWebKey, activate }

AppCheckPlan planAppCheck({
  required bool enabled,
  required bool isWeb,
  required String webKey,
}) {
  if (!enabled) return AppCheckPlan.off;
  if (isWeb && webKey.trim().isEmpty) return AppCheckPlan.missingWebKey;
  return AppCheckPlan.activate;
}

/// Crash reports are collected only from release builds on Android/iOS
/// (Crashlytics has no web support), and can be switched off with
/// `--dart-define=CRASH_REPORTING=false`.
bool shouldCollectCrashes({
  required bool isDebug,
  required bool isWeb,
  required bool optedOut,
}) => !isDebug && !isWeb && !optedOut;

/// Starts App Check and crash reporting. Must run after Firebase is
/// initialised. Never throws: monitoring must not stop the app from starting.
Future<void> setUpMonitoring({
  bool appCheckEnabled = const bool.fromEnvironment('APP_CHECK_ENABLED'),
  String appCheckWebKey = const String.fromEnvironment('APP_CHECK_WEB_KEY'),
  bool crashReportingOptOut = !const bool.fromEnvironment(
    'CRASH_REPORTING',
    defaultValue: true,
  ),
}) async {
  switch (planAppCheck(
    enabled: appCheckEnabled,
    isWeb: kIsWeb,
    webKey: appCheckWebKey,
  )) {
    case AppCheckPlan.off:
      break;
    case AppCheckPlan.missingWebKey:
      AppLogger.warning(
        'App Check requested for web but APP_CHECK_WEB_KEY is empty; skipped.',
        tag: 'Monitoring',
      );
    case AppCheckPlan.activate:
      try {
        await FirebaseAppCheck.instance.activate(
          providerWeb: kIsWeb ? ReCaptchaV3Provider(appCheckWebKey) : null,
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (e, st) {
        AppLogger.error(
          'App Check activation failed',
          tag: 'Monitoring',
          error: e,
          stackTrace: st,
        );
      }
  }

  if (!shouldCollectCrashes(
    isDebug: kDebugMode,
    isWeb: kIsWeb,
    optedOut: crashReportingOptOut,
  )) {
    return;
  }
  try {
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(true);
    AppLogger.errorSink = (message, error, stackTrace) {
      // Stable, non-sensitive text only (see AppLogger's rules).
      crashlytics.recordError(
        error ?? message,
        stackTrace,
        reason: message,
        fatal: false,
      );
    };
  } catch (e, st) {
    AppLogger.error(
      'Crash reporting could not start',
      tag: 'Monitoring',
      error: e,
      stackTrace: st,
    );
  }
}
