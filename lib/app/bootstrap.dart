import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/config/env_config.dart';
import '../core/config/env_config_provider.dart';
import '../core/config/firebase_initializer.dart';
import '../core/logging/app_logger.dart';
import 'app.dart';
import 'startup_error_app.dart';

/// Routes otherwise-unhandled Flutter and platform errors to [AppLogger]
/// (the single place a crash-reporting backend would be attached). The user
/// sees the normal error widgets; nothing here shows technical detail.
///
/// Returns the previous handlers so tests can restore them.
({FlutterExceptionHandler? flutter, ErrorCallback? platform})
installErrorHandlers() {
  final previousFlutter = FlutterError.onError;
  final previousPlatform = PlatformDispatcher.instance.onError;
  FlutterError.onError = (details) {
    AppLogger.error(
      'Unhandled Flutter error',
      tag: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
    // Keep the default console report in debug builds.
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error(
      'Unhandled platform error',
      tag: 'PlatformDispatcher',
      error: error,
      stackTrace: stack,
    );
    return true; // handled: do not terminate the app
  };
  return (flutter: previousFlutter, platform: previousPlatform);
}

/// Decides whether the environment selected by the entry point agrees with
/// an explicit `--dart-define=APP_ENV=…`. Returns an error code or null.
///
/// Missing define: fine (the entry point *is* the selection). Present but
/// unknown, or naming another environment: an error — the operator asked
/// for something the binary is not, and must be told rather than guessed at.
String? checkEnvironmentDefine(EnvConfig config, String appEnvDefine) {
  final raw = appEnvDefine.trim();
  if (raw.isEmpty) return null;
  final requested = AppEnvironment.tryParse(raw);
  if (requested == null) return 'ENV_INVALID';
  if (requested != config.environment) return 'ENV_DEFINE_MISMATCH';
  return null;
}

/// Shared startup path for every `main_*.dart` entry point.
///
/// Resolves nothing implicitly: the caller passes the [EnvConfig] it was built
/// for. Firebase is initialised exactly once through [FirebaseInitializer];
/// on any configuration problem the app stops on a [StartupErrorApp] rather
/// than running against placeholders, the wrong project, or nothing.
Future<void> bootstrap(
  EnvConfig envConfig, {
  String appEnvDefine = const String.fromEnvironment('APP_ENV'),
  FirebaseInitializer initializer = const FirebaseInitializer(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();

  final defineProblem = checkEnvironmentDefine(envConfig, appEnvDefine);
  if (defineProblem != null) {
    AppLogger.error(
      'Environment selection rejected ($defineProblem): entry point is '
      '${envConfig.environment.name}.',
      tag: 'Startup',
    );
    runApp(StartupErrorApp(appName: envConfig.appName, code: defineProblem));
    return;
  }

  final result = await initializer.initialize(envConfig);
  if (!result.ready) {
    runApp(StartupErrorApp(appName: envConfig.appName, code: result.errorCode));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [envConfigProvider.overrideWithValue(envConfig)],
      child: const App(),
    ),
  );
}
