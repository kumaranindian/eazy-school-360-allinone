import 'manual_models.dart';

/// Saved progress of one user across guides. Content is bundled with the app;
/// only this is stored.
abstract class ManualProgressRepository {
  Stream<Map<String, ManualProgress>> watch(String userId);

  Future<void> save(String userId, ManualProgress progress);

  Future<void> reset(String userId, String guideId);
}
