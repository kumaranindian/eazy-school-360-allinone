/// The version shown in the app footer. Keep in step with `version:` in
/// `pubspec.yaml` (`name+build`) — `test/core/app_version_test.dart` fails
/// if they drift, so a build can never advertise the wrong number.
const String appVersionName = '1.1.0';
const String appBuildNumber = '13';

/// "v1.1.0 (13)".
const String appVersionLabel = 'v$appVersionName ($appBuildNumber)';
