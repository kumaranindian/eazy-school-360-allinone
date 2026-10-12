import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env_config.dart';

/// Overridden once, at startup, in `app/bootstrap.dart` with the resolved
/// [EnvConfig] for whichever `main_*.dart` entry point launched the app.
/// Reading this before that override is a programming error, not a
/// recoverable runtime state — hence the `throw` rather than a nullable
/// default.
final envConfigProvider = Provider<EnvConfig>((ref) {
  throw UnimplementedError(
    'envConfigProvider must be overridden in bootstrap() before use.',
  );
});
