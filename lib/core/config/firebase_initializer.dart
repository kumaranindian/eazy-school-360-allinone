import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

import '../logging/app_logger.dart';
import 'env_config.dart';
import 'firebase_config_validator.dart';

/// The part of `firebase_core` the initializer needs, so tests can supply a
/// fake and prove "initialised once, with the right options".
abstract class FirebaseCoreGateway {
  /// Options of the already-initialised default app, or null if none.
  FirebaseOptions? get defaultAppOptions;

  /// Initialises the default app and returns the options it ended up with.
  Future<FirebaseOptions> initializeDefault(FirebaseOptions options);
}

class RealFirebaseCoreGateway implements FirebaseCoreGateway {
  const RealFirebaseCoreGateway();

  @override
  FirebaseOptions? get defaultAppOptions {
    for (final app in Firebase.apps) {
      if (app.name == defaultFirebaseAppName) return app.options;
    }
    return null;
  }

  @override
  Future<FirebaseOptions> initializeDefault(FirebaseOptions options) async {
    final app = await Firebase.initializeApp(options: options);
    return app.options;
  }
}

/// Outcome of [FirebaseInitializer.initialize].
class FirebaseInitResult {
  /// Null when Firebase is ready.
  final String? errorCode;

  const FirebaseInitResult.ready() : errorCode = null;
  const FirebaseInitResult.failed(String this.errorCode);

  bool get ready => errorCode == null;
}

/// The single Firebase start-up path for every platform and entry point:
/// validate the selected environment's options → refuse a leftover default
/// app of another project → initialise exactly once → verify the active
/// project is the intended one.
class FirebaseInitializer {
  final FirebaseCoreGateway _core;

  const FirebaseInitializer([this._core = const RealFirebaseCoreGateway()]);

  Future<FirebaseInitResult> initialize(
    EnvConfig config, {
    bool? isWeb,
    TargetPlatform? platform,
  }) async {
    final issues = FirebaseConfigValidator.validate(
      config,
      isWeb: isWeb,
      platform: platform,
    );
    if (issues.isNotEmpty) {
      for (final i in issues) {
        AppLogger.error('Firebase configuration problem: $i', tag: 'Startup');
      }
      return FirebaseInitResult.failed(issues.first.code);
    }

    final expected = config.firebaseOptions.projectId;
    final existing = _core.defaultAppOptions;
    if (existing != null) {
      if (existing.projectId != expected) {
        AppLogger.error(
          'A Firebase app for another project is already initialised '
          '(have ${existing.projectId}, need $expected).',
          tag: 'Startup',
        );
        return const FirebaseInitResult.failed('ENV_APP_ALREADY_INITIALISED');
      }
      AppLogger.debug('Firebase already initialised; reusing.', tag: 'Startup');
      return const FirebaseInitResult.ready();
    }

    try {
      final active = await _core.initializeDefault(config.firebaseOptions);
      if (active.projectId != expected) {
        AppLogger.error(
          'Active Firebase project ${active.projectId} is not the selected '
          'environment\'s project $expected.',
          tag: 'Startup',
        );
        return const FirebaseInitResult.failed('ENV_ACTIVE_PROJECT_MISMATCH');
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'Firebase initialisation failed (${config.environment.name}).',
        tag: 'Startup',
        error: error,
        stackTrace: stackTrace,
      );
      return const FirebaseInitResult.failed('FIREBASE_INIT_FAILED');
    }
    AppLogger.debug(config.diagnostics(), tag: 'Startup');
    return const FirebaseInitResult.ready();
  }
}
