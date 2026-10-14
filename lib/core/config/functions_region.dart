import 'package:cloud_functions/cloud_functions.dart';

/// Region the Cloud Functions are deployed to. Must equal `FUNCTIONS_REGION`
/// in `functions/.env` (which must match the Firestore database region).
/// Override per build with `--dart-define=FUNCTIONS_REGION=...`.
const String functionsRegion = String.fromEnvironment(
  'FUNCTIONS_REGION',
  defaultValue: 'asia-south1',
);

FirebaseFunctions appFunctions() =>
    FirebaseFunctions.instanceFor(region: functionsRegion);
