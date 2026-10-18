import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Region the Cloud Functions are deployed to. Must equal `FUNCTIONS_REGION`
/// in `functions/.env` (which must match the Firestore database region).
/// Override per build with `--dart-define=FUNCTIONS_REGION=...`.
const String functionsRegion = String.fromEnvironment(
  'FUNCTIONS_REGION',
  defaultValue: 'asia-south1',
);

FirebaseFunctions appFunctions() {
  try {
    return FirebaseFunctions.instanceFor(region: functionsRegion);
  } catch (error, stackTrace) {
    // Printed in release too: this failing means no callable can be made.
    debugPrint(
      '[functions] could not create instance for region=$functionsRegion: '
      '${error.runtimeType}'
      '${kDebugMode ? ': $error\n$stackTrace' : ''}',
    );
    rethrow;
  }
}
