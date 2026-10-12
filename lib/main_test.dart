import 'app/bootstrap.dart';
import 'core/config/env/environments.dart';

/// TEST entry point. Example: (no Firebase project configured — refuses to start)
/// The optional APP_ENV define must agree with this entry point.
Future<void> main() async {
  await bootstrap(testEnvConfig());
}
