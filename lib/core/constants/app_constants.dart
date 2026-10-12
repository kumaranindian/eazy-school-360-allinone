/// App-wide literals that aren't environment-specific (see [EnvConfig] for
/// those) and aren't routing (see `core/routing/app_routes.dart`).
abstract final class AppConstants {
  static const Duration networkTimeout = Duration(seconds: 20);
  static const Duration snackBarDuration = Duration(seconds: 4);
  static const int minPasswordLength = 8;

  /// Every newly self-signed-up school gets exactly one branch at creation
  /// time, with this fixed id — see `FIRESTORE_ARCHITECTURE.md` →
  /// "School creation" for why a deterministic id (rather than a generated
  /// one) is what makes the two-phase creation flow's second phase safe
  /// under Firestore rules.
  static const String defaultBranchId = 'main';
}
