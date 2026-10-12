import 'app/bootstrap.dart';
import 'core/config/env/environments.dart';

/// PROD entry point. Example: flutter build web --release -t lib/main_prod.dart --dart-define=APP_ENV=prod
/// The optional APP_ENV define must agree with this entry point.
Future<void> main() async {
  await bootstrap(prodEnvConfig());
}
