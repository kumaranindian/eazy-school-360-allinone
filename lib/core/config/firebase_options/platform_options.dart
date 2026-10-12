import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// One Firebase project has a *separate app registration per platform*
/// (web, Android, iOS/macOS), each with its own `appId` and API key, so a
/// single options object cannot serve all of them. Each environment file
/// supplies one block per platform and this picks the running one.
class FirebaseOptionSet {
  final FirebaseOptions web;
  final FirebaseOptions android;
  final FirebaseOptions ios;
  final FirebaseOptions? macos;

  const FirebaseOptionSet({
    required this.web,
    required this.android,
    required this.ios,
    this.macos,
  });

  /// The options for the running platform (or the given one, for tests).
  FirebaseOptions resolve({bool? isWeb, TargetPlatform? platform}) {
    if (isWeb ?? kIsWeb) return web;
    switch (platform ?? defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos ?? ios;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        throw UnsupportedError(
          'EazySchool 360 has no Firebase registration for '
          '${platform ?? defaultTargetPlatform}.',
        );
    }
  }
}

FirebaseOptions selectPlatformOptions({
  required FirebaseOptions web,
  required FirebaseOptions android,
  required FirebaseOptions ios,
  FirebaseOptions? macos,
}) => FirebaseOptionSet(
  web: web,
  android: android,
  ios: ios,
  macos: macos,
).resolve();

/// True for the checked-in placeholder values.
bool isPlaceholder(String value) => value.startsWith('REPLACE_');
