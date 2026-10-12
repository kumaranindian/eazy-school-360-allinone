/// The device-side messaging service, behind an interface so registration
/// logic is testable without Firebase.
abstract class PushGateway {
  /// Whether this build can receive push at all (not web, for now).
  bool get supported;

  /// `android` or `ios`, as stored with the device token.
  String get platform;

  /// Asks the OS for permission (a prompt on iOS and Android 13+). True when
  /// notifications are allowed.
  Future<bool> requestPermission();

  /// This device's token, or null when unavailable.
  Future<String?> getToken();

  /// Emits whenever the token changes.
  Stream<String> get onTokenRefresh;

  /// Invalidates the token (sign-out), so the device stops receiving the
  /// previous user's notifications.
  Future<void> deleteToken();
}
