import 'package:firebase_core/firebase_core.dart';

import 'app_environment.dart';
import 'env/environments.dart';
import 'firebase_options/platform_options.dart';

/// Non-secret, environment-scoped configuration.
///
/// This is the single place that knows how "dev", "test", "uat" and "prod"
/// differ. Nothing else in the app should branch on [AppEnvironment]
/// directly — inject an [EnvConfig] instance (via the Riverpod provider in
/// `lib/app/bootstrap.dart`) and read from it instead.
///
/// Firebase API keys/app IDs embedded in [FirebaseOptions] are public client
/// identifiers (see SECURITY_ARCHITECTURE.md), not secrets, but they are
/// environment-specific: each environment has its own options and an
/// explicit list of project ids it must never resolve to.
class EnvConfig {
  final AppEnvironment environment;
  final String appName;
  final FirebaseOptions firebaseOptions;

  /// Project ids this environment must never initialise (the other
  /// environments' projects). Checked at startup.
  final Set<String> forbiddenProjectIds;

  const EnvConfig({
    required this.environment,
    required this.appName,
    required this.firebaseOptions,
    this.forbiddenProjectIds = const {},
  });

  /// True while the options still carry placeholder values. Such a build
  /// cannot talk to a real project and must not start.
  bool get hasPlaceholderFirebaseOptions =>
      isPlaceholder(firebaseOptions.apiKey) ||
      isPlaceholder(firebaseOptions.appId) ||
      isPlaceholder(firebaseOptions.messagingSenderId);

  /// The configuration of [environment]. Used by tests and by the generic
  /// `main.dart`; the dedicated entry points call the per-environment
  /// factories directly so a build compiles only its own options.
  factory EnvConfig.forEnvironment(AppEnvironment environment) {
    switch (environment) {
      case AppEnvironment.dev:
        return devEnvConfig();
      case AppEnvironment.test:
        return testEnvConfig();
      case AppEnvironment.uat:
        return uatEnvConfig();
      case AppEnvironment.prod:
        return prodEnvConfig();
    }
  }

  /// Safe, non-secret description for logs and diagnostics.
  String diagnostics() =>
      'env=${environment.name} project=${firebaseOptions.projectId} '
      'app=${_maskId(firebaseOptions.appId)}';

  static String _maskId(String id) => id.length <= 12
      ? '***'
      : '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
}
