/// Whether the OS / browser lets this app show notifications.
enum PushPermission { granted, denied, undetermined }

/// The device-side messaging service, behind an interface so registration
/// logic is testable without Firebase.
abstract class PushGateway {
  /// Whether this build can receive push at all. Web only when the build was
  /// given a VAPID key (`--dart-define=FCM_VAPID_KEY=...`).
  bool get supported;

  /// `android`, `ios` or `web`, as stored with the device token.
  String get platform;

  /// Browsers only honour a permission prompt that follows a click, so the
  /// app must not ask on its own there; it waits for the user to press
  /// "Enable".
  bool get requiresUserGesture;

  /// The current permission, without prompting.
  Future<PushPermission> permission();

  /// Asks the OS for permission (a prompt on iOS, Android 13+ and browsers).
  /// True when notifications are allowed.
  Future<bool> requestPermission();

  /// This device's token, or null when unavailable.
  Future<String?> getToken();

  /// Emits whenever the token changes.
  Stream<String> get onTokenRefresh;

  /// Invalidates the token (sign-out), so the device stops receiving the
  /// previous user's notifications.
  Future<void> deleteToken();

  /// Prepares presentation (e.g. iOS foreground alerts and sound). Idempotent.
  Future<void> initialize();

  /// The `data` of a notification the user tapped while the app was in the
  /// background.
  Stream<Map<String, String>> get onOpened;

  /// The `data` of the notification that launched the app from a closed
  /// state, if any (consumed once).
  Future<Map<String, String>?> launchedBy();
}
