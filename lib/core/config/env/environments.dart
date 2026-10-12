import '../app_environment.dart';
import '../env_config.dart';
import '../firebase_options/firebase_options_dev.dart';
import '../firebase_options/firebase_options_prod.dart';
import '../firebase_options/firebase_options_test.dart';
import '../firebase_options/firebase_options_uat.dart';
import '../known_firebase_projects.dart';

/// One factory per environment. Entry points call exactly one of these, so
/// a `main_prod.dart` build never references the development options.
EnvConfig devEnvConfig() => EnvConfig(
  environment: AppEnvironment.dev,
  appName: 'EazySchool 360 (Dev)',
  firebaseOptions: devFirebaseOptions,
  forbiddenProjectIds: const {kProdFirebaseProjectId},
);

EnvConfig prodEnvConfig() => EnvConfig(
  environment: AppEnvironment.prod,
  appName: 'EazySchool 360',
  firebaseOptions: prodFirebaseOptions,
  forbiddenProjectIds: const {kDevFirebaseProjectId},
);

/// `test` and `uat` have no Firebase project configured in this repository;
/// they hold placeholders and refuse to start (they are never aliased to dev
/// or prod).
EnvConfig testEnvConfig() => EnvConfig(
  environment: AppEnvironment.test,
  appName: 'EazySchool 360 (Test)',
  firebaseOptions: testFirebaseOptions,
  forbiddenProjectIds: const {kDevFirebaseProjectId, kProdFirebaseProjectId},
);

EnvConfig uatEnvConfig() => EnvConfig(
  environment: AppEnvironment.uat,
  appName: 'EazySchool 360 (UAT)',
  firebaseOptions: uatFirebaseOptions,
  forbiddenProjectIds: const {kDevFirebaseProjectId, kProdFirebaseProjectId},
);
