import 'package:firebase_core/firebase_core.dart';

import 'platform_options.dart';

/// PLACEHOLDER Firebase options for the `test` environment (Test).
///
/// No real Firebase project is configured in the repository. The project id
/// and bucket below are *suggested names only* — they are not verified to
/// exist and must be replaced with the owner's real ones.
///
/// To configure (see docs/milestone-12a-blocker-closure.md, "Owner setup"):
/// 1. Create the Firebase project for `test` and register a Web, an Android
///    (`com.avail404.eazyschool.eazyschool360`) and an iOS app
///    (same bundle id).
/// 2. Run `flutterfire configure --project=YOUR_PROJECT_ID
///    --out=/tmp/firebase_options_test.dart` (scratch output).
/// 3. Copy each platform's `FirebaseOptions(...)` from that output into the
///    matching block below. Keep the `selectPlatformOptions` wrapper.
/// 4. Never reuse another environment's project here.
///
/// These values are public client identifiers, not secrets (see
/// SECURITY_ARCHITECTURE.md); access is enforced by Security Rules.
final testFirebaseOptions = selectPlatformOptions(
  web: const FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    messagingSenderId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    projectId: 'avail404-eazyschool360-test',
    storageBucket: 'avail404-eazyschool360-test.appspot.com',
    authDomain: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
  ),
  android: const FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    messagingSenderId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    projectId: 'avail404-eazyschool360-test',
    storageBucket: 'avail404-eazyschool360-test.appspot.com',
  ),
  ios: const FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    messagingSenderId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    projectId: 'avail404-eazyschool360-test',
    storageBucket: 'avail404-eazyschool360-test.appspot.com',
    iosBundleId: 'com.avail404.eazyschool.eazyschool360',
  ),
);
