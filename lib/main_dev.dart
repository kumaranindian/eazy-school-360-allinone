import 'app/bootstrap.dart';
import 'core/config/env/environments.dart';

/// DEV entry point. Example: flutter run -t lib/main_dev.dart --dart-define=APP_ENV=dev
/// The optional APP_ENV define must agree with this entry point.
Future<void> main() async {
  await bootstrap(devEnvConfig());
}
