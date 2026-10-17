import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/push_gateway.dart';

/// The public Web Push (VAPID) key of the Firebase project, from
/// Console > Project settings > Cloud Messaging > Web Push certificates. It is
/// a public key, but it differs per environment, so it is a build define.
const String fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

class FirebasePushGateway implements PushGateway {
  FirebasePushGateway();

  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  bool _initialized = false;

  @override
  bool get supported => kIsWeb
      ? fcmVapidKey.isNotEmpty
      : (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

  @override
  String get platform => kIsWeb
      ? 'web'
      : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  @override
  bool get requiresUserGesture => kIsWeb;

  @override
  Future<PushPermission> permission() async {
    final s = await _fm.getNotificationSettings();
    return switch (s.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.undetermined,
    };
  }

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() =>
      _fm.getToken(vapidKey: kIsWeb ? fcmVapidKey : null);

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fm.deleteToken();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // iOS shows nothing for a push that arrives while the app is open unless
    // told to; the in-app feed alerts too, so keep the system banner + sound.
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Map<String, String> _data(RemoteMessage m) => {
    for (final e in m.data.entries) e.key: '${e.value}',
  };

  @override
  Stream<Map<String, String>> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.map(_data);

  @override
  Future<Map<String, String>?> launchedBy() async {
    final m = await _fm.getInitialMessage();
    return m == null ? null : _data(m);
  }
}
