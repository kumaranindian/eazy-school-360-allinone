import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/push_gateway.dart';

class FirebasePushGateway implements PushGateway {
  FirebasePushGateway();

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  // Web needs a service worker and a VAPID key; not set up yet.
  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fm.deleteToken();
}
