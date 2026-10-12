/// The deployment environment the app is currently running under.
///
/// Selected explicitly: by launching one of the `lib/main_*.dart` entry
/// points, optionally cross-checked with `--dart-define=APP_ENV=<name>`
/// (the generic `lib/main.dart` *requires* that define). There is no
/// default: an unknown or missing value is a startup error, never a silent
/// fall-back to development (or production).
enum AppEnvironment {
  dev,
  test,
  uat,
  prod;

  /// The environment named [name] (case-insensitive, trimmed), or `null`
  /// when [name] is empty or not one of the known environments.
  static AppEnvironment? tryParse(String? name) {
    final n = name?.toLowerCase().trim() ?? '';
    for (final e in AppEnvironment.values) {
      if (e.name == n) return e;
    }
    return null;
  }

  bool get isProd => this == AppEnvironment.prod;

  bool get isDev => this == AppEnvironment.dev;

  /// Whether verbose debug logging and dev-only affordances should show.
  bool get isDebuggable =>
      this == AppEnvironment.dev || this == AppEnvironment.test;
}
