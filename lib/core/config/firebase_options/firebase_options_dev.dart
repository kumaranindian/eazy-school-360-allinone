import 'package:firebase_core/firebase_core.dart';

import 'platform_options.dart';

/// Firebase options for the `dev` environment — project
/// `eazy-school-360-dev`.
///
/// Values come from the owner-supplied registrations, kept for reference in
/// `config/firebase/dev/` (Android `google-services.json`, iOS
/// `GoogleService-Info.plist`) and the web app snippet. A test
/// (`test/core/firebase_config_files_test.dart`) fails if these blocks and
/// those files ever disagree.
///
/// These are public client identifiers, not secrets; access is enforced by
/// Security Rules. Do not paste another environment's values here.
const devFirebaseOptionSet = FirebaseOptionSet(
  web: FirebaseOptions(
    apiKey: 'AIzaSyBMbwxh2722KaYflOiTKwEE5IJBumgwS1w',
    authDomain: 'eazy-school-360-dev.firebaseapp.com',
    projectId: 'eazy-school-360-dev',
    storageBucket: 'eazy-school-360-dev.firebasestorage.app',
    messagingSenderId: '894913996276',
    appId: '1:894913996276:web:3156b08ef6b3e2e22ac5a1',
    measurementId: 'G-RXVRBKJVLQ',
  ),
  android: FirebaseOptions(
    apiKey: 'AIzaSyDoLavysY7zxTRtlnr8hLZrNRDlfJn-2ag',
    appId: '1:894913996276:android:b1f908350a1773fc2ac5a1',
    messagingSenderId: '894913996276',
    projectId: 'eazy-school-360-dev',
    storageBucket: 'eazy-school-360-dev.firebasestorage.app',
  ),
  ios: FirebaseOptions(
    apiKey: 'AIzaSyAuuA2x-1cEMvJV7u0iGbegf2Azc-v6dfY',
    appId: '1:894913996276:ios:e1df22473076610b2ac5a1',
    messagingSenderId: '894913996276',
    projectId: 'eazy-school-360-dev',
    storageBucket: 'eazy-school-360-dev.firebasestorage.app',
    iosBundleId: 'com.avail404.eazyschool.eazyschool360',
  ),
);

/// The options for the running platform.
final devFirebaseOptions = devFirebaseOptionSet.resolve();
