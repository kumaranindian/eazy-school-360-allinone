import 'package:firebase_core/firebase_core.dart';

import 'platform_options.dart';

/// Firebase options for the `prod` environment — project
/// `eazy-school-360-prod`.
///
/// All three platforms are configured from the owner-supplied registrations
/// kept for reference in `config/firebase/prod/` (Android
/// `google-services.json`, iOS `GoogleService-Info.plist`) and the web app
/// snippet. `test/core/firebase_environment_test.dart` fails if these blocks
/// and those files ever disagree.
///
/// Public client identifiers, not secrets; access is enforced by Security
/// Rules. Do not paste another environment's values here.
const prodFirebaseOptionSet = FirebaseOptionSet(
  web: FirebaseOptions(
    apiKey: 'AIzaSyDqMV_4c5y8OWhNtcjR6UOxRkbjjGEHP1w',
    authDomain: 'eazy-school-360-prod.firebaseapp.com',
    projectId: 'eazy-school-360-prod',
    storageBucket: 'eazy-school-360-prod.firebasestorage.app',
    messagingSenderId: '97832195228',
    appId: '1:97832195228:web:5bf9950a31a2e9753b8959',
    measurementId: 'G-0FT377C1LJ',
  ),
  android: FirebaseOptions(
    apiKey: 'AIzaSyAoWZsjOjYVbUqsDNBakGuV8LXH_fxNWPg',
    appId: '1:97832195228:android:eef59136340e59333b8959',
    messagingSenderId: '97832195228',
    projectId: 'eazy-school-360-prod',
    storageBucket: 'eazy-school-360-prod.firebasestorage.app',
  ),
  ios: FirebaseOptions(
    apiKey: 'AIzaSyC0CyumCzeBobNBuKRz3ft2uEIS4JBC7eM',
    appId: '1:97832195228:ios:92d868d0c30f58573b8959',
    messagingSenderId: '97832195228',
    projectId: 'eazy-school-360-prod',
    storageBucket: 'eazy-school-360-prod.firebasestorage.app',
    iosBundleId: 'com.avail404.eazyschool.eazyschool360',
  ),
);

/// The options for the running platform.
final prodFirebaseOptions = prodFirebaseOptionSet.resolve();
