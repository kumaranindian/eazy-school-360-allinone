import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/startup_error_app.dart';
import 'core/config/app_environment.dart';
import 'core/config/env_config.dart';

/// Generic entry point: the environment MUST be chosen explicitly with
/// `--dart-define=APP_ENV=dev|prod` (or use `lib/main_dev.dart` /
/// `lib/main_prod.dart`). No value, or an unknown one, stops at a startup
/// error — there is no default environment.
Future<void> main() async {
  const raw = String.fromEnvironment('APP_ENV');
  final env = AppEnvironment.tryParse(raw);
  if (env == null) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      StartupErrorApp(
        appName: 'EazySchool 360',
        code: raw.trim().isEmpty ? 'ENV_NOT_SELECTED' : 'ENV_INVALID',
      ),
    );
    return;
  }
  await bootstrap(EnvConfig.forEnvironment(env));
}
