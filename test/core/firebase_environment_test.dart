import 'dart:convert';
import 'dart:io';

import 'package:eazy_school_360/app/bootstrap.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/firebase_config_validator.dart';
import 'package:eazy_school_360/core/config/firebase_initializer.dart';
import 'package:eazy_school_360/core/config/firebase_options/firebase_options_dev.dart';
import 'package:eazy_school_360/core/config/firebase_options/firebase_options_prod.dart';
import 'package:eazy_school_360/core/config/known_firebase_projects.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCore implements FirebaseCoreGateway {
  FirebaseOptions? existing;
  final List<FirebaseOptions> initialised = [];
  Object? failWith;
  FirebaseOptions? returnInstead;

  @override
  FirebaseOptions? get defaultAppOptions => existing;

  @override
  Future<FirebaseOptions> initializeDefault(FirebaseOptions options) async {
    if (failWith != null) throw failWith!;
    initialised.add(options);
    existing = returnInstead ?? options;
    return existing!;
  }
}

Set<String> _codes(EnvConfig c, {bool web = false, TargetPlatform? p}) => {
  for (final i in FirebaseConfigValidator.validate(c, isWeb: web, platform: p))
    i.code,
};

EnvConfig _withOptions(
  AppEnvironment env,
  FirebaseOptions o, {
  Set<String> forbidden = const {},
}) => EnvConfig(
  environment: env,
  appName: 'x',
  firebaseOptions: o,
  forbiddenProjectIds: forbidden,
);

/// The environment's config as it would be on one platform.
EnvConfig _on(AppEnvironment env, String platform) {
  final full = EnvConfig.forEnvironment(env);
  final set = env == AppEnvironment.prod
      ? prodFirebaseOptionSet
      : devFirebaseOptionSet;
  final options = switch (platform) {
    'web' => set.web,
    'android' => set.android,
    _ => set.ios,
  };
  return _withOptions(env, options, forbidden: full.forbiddenProjectIds);
}

void main() {
  group('environment selection', () {
    test('parses known names; empty and unknown are not silently dev', () {
      expect(AppEnvironment.tryParse('dev'), AppEnvironment.dev);
      expect(AppEnvironment.tryParse(' PROD '), AppEnvironment.prod);
      expect(AppEnvironment.tryParse(''), isNull);
      expect(AppEnvironment.tryParse(null), isNull);
      expect(AppEnvironment.tryParse('staging'), isNull);
      expect(AppEnvironment.tryParse('production'), isNull);
    });

    test('the define must agree with the entry point', () {
      final dev = EnvConfig.forEnvironment(AppEnvironment.dev);
      expect(checkEnvironmentDefine(dev, ''), isNull);
      expect(checkEnvironmentDefine(dev, 'dev'), isNull);
      expect(checkEnvironmentDefine(dev, 'prod'), 'ENV_DEFINE_MISMATCH');
      expect(checkEnvironmentDefine(dev, 'qa'), 'ENV_INVALID');
    });
  });

  group('the configured projects', () {
    test('dev and prod resolve to their own, different projects', () {
      for (final set in [devFirebaseOptionSet, prodFirebaseOptionSet]) {
        for (final o in [set.web, set.android, set.ios]) {
          expect(
            o.projectId,
            set == devFirebaseOptionSet
                ? kDevFirebaseProjectId
                : kProdFirebaseProjectId,
          );
        }
      }
      expect(kDevFirebaseProjectId, isNot(kProdFirebaseProjectId));
      final dev = EnvConfig.forEnvironment(AppEnvironment.dev);
      final prod = EnvConfig.forEnvironment(AppEnvironment.prod);
      expect(dev.forbiddenProjectIds, {kProdFirebaseProjectId});
      expect(prod.forbiddenProjectIds, {kDevFirebaseProjectId});
      expect(
        devFirebaseOptionSet.web.appId,
        isNot(prodFirebaseOptionSet.web.appId),
      );
      expect(
        devFirebaseOptionSet.web.apiKey,
        isNot(prodFirebaseOptionSet.web.apiKey),
      );
    });

    test('dev is valid on web, Android and iOS', () {
      expect(_codes(_on(AppEnvironment.dev, 'web'), web: true), isEmpty);
      expect(
        _codes(_on(AppEnvironment.dev, 'android'), p: TargetPlatform.android),
        isEmpty,
      );
      expect(
        _codes(_on(AppEnvironment.dev, 'ios'), p: TargetPlatform.iOS),
        isEmpty,
      );
    });

    test('prod is valid on web, Android and iOS', () {
      expect(_codes(_on(AppEnvironment.prod, 'web'), web: true), isEmpty);
      expect(
        _codes(_on(AppEnvironment.prod, 'android'), p: TargetPlatform.android),
        isEmpty,
      );
      expect(
        _codes(_on(AppEnvironment.prod, 'ios'), p: TargetPlatform.iOS),
        isEmpty,
      );
      expect(
        prodFirebaseOptionSet.android.apiKey,
        isNot(devFirebaseOptionSet.android.apiKey),
      );
      expect(
        prodFirebaseOptionSet.ios.appId,
        isNot(devFirebaseOptionSet.ios.appId),
      );
    });

    test('an unconfigured platform block is refused, never run', () {
      const placeholder = FirebaseOptions(
        apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
        appId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
        messagingSenderId: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
        projectId: kProdFirebaseProjectId,
        storageBucket: 'x',
      );
      final c = _withOptions(
        AppEnvironment.prod,
        placeholder,
        forbidden: const {kDevFirebaseProjectId},
      );
      expect(c.hasPlaceholderFirebaseOptions, isTrue);
      expect(
        _codes(c, p: TargetPlatform.android),
        contains('PLACEHOLDER_API_KEY'),
      );
    });
  });

  group('validation catches mix-ups', () {
    test('a production build that resolves the development project', () {
      final c = _withOptions(
        AppEnvironment.prod,
        devFirebaseOptionSet.web,
        forbidden: const {kDevFirebaseProjectId},
      );
      expect(_codes(c, web: true), contains('ENV_PROJECT_MISMATCH'));
    });

    test('an app id registered for another platform or project', () {
      final web = devFirebaseOptionSet.web;
      // an Android app id used on web
      final wrongKind = _withOptions(
        AppEnvironment.dev,
        FirebaseOptions(
          apiKey: web.apiKey,
          appId: devFirebaseOptionSet.android.appId,
          messagingSenderId: web.messagingSenderId,
          projectId: web.projectId,
          authDomain: web.authDomain,
          storageBucket: web.storageBucket,
        ),
      );
      expect(_codes(wrongKind, web: true), contains('APP_ID_PLATFORM'));
      // the other project's sender id
      final wrongSender = _withOptions(
        AppEnvironment.dev,
        FirebaseOptions(
          apiKey: web.apiKey,
          appId: web.appId,
          messagingSenderId: prodFirebaseOptionSet.web.messagingSenderId,
          projectId: web.projectId,
          authDomain: web.authDomain,
          storageBucket: web.storageBucket,
        ),
      );
      expect(
        _codes(wrongSender, web: true),
        contains('APP_ID_SENDER_MISMATCH'),
      );
    });

    test('web needs a matching authDomain; iOS needs the right bundle id', () {
      final web = devFirebaseOptionSet.web;
      final noDomain = _withOptions(
        AppEnvironment.dev,
        FirebaseOptions(
          apiKey: web.apiKey,
          appId: web.appId,
          messagingSenderId: web.messagingSenderId,
          projectId: web.projectId,
          storageBucket: web.storageBucket,
        ),
      );
      expect(_codes(noDomain, web: true), contains('MISSING_AUTH_DOMAIN'));
      final ios = devFirebaseOptionSet.ios;
      final badBundle = _withOptions(
        AppEnvironment.dev,
        FirebaseOptions(
          apiKey: ios.apiKey,
          appId: ios.appId,
          messagingSenderId: ios.messagingSenderId,
          projectId: ios.projectId,
          storageBucket: ios.storageBucket,
          iosBundleId: 'com.example.other',
        ),
      );
      expect(
        _codes(badBundle, p: TargetPlatform.iOS),
        contains('IOS_BUNDLE_ID'),
      );
    });

    test('diagnostics never include the key or the full app id', () {
      final c = EnvConfig.forEnvironment(AppEnvironment.dev);
      final d = c.diagnostics();
      expect(d, contains('env=dev'));
      expect(d, contains(kDevFirebaseProjectId));
      expect(d, isNot(contains(c.firebaseOptions.apiKey)));
      expect(d, isNot(contains(c.firebaseOptions.appId)));
    });
  });

  group('initialisation', () {
    EnvConfig dev() => _on(AppEnvironment.dev, 'web');

    test('initialises exactly once with the selected options', () async {
      final core = _FakeCore();
      final init = FirebaseInitializer(core);
      final r1 = await init.initialize(dev(), isWeb: true);
      final r2 = await init.initialize(dev(), isWeb: true);
      expect(r1.ready, isTrue);
      expect(r2.ready, isTrue);
      expect(core.initialised, hasLength(1));
      expect(core.initialised.single.projectId, kDevFirebaseProjectId);
      expect(core.initialised.single.appId, devFirebaseOptionSet.web.appId);
    });

    test('placeholder options never reach Firebase', () async {
      final core = _FakeCore();
      final r = await FirebaseInitializer(
        core,
      ).initialize(EnvConfig.forEnvironment(AppEnvironment.uat), isWeb: true);
      expect(r.ready, isFalse);
      expect(r.errorCode, startsWith('PLACEHOLDER_'));
      expect(core.initialised, isEmpty);
    });

    test('a leftover app of another project is refused, not reused', () async {
      final core = _FakeCore()..existing = prodFirebaseOptionSet.web;
      final r = await FirebaseInitializer(core).initialize(dev(), isWeb: true);
      expect(r.errorCode, 'ENV_APP_ALREADY_INITIALISED');
      expect(core.initialised, isEmpty);
    });

    test('an already-initialised app of the same project is reused', () async {
      final core = _FakeCore()..existing = devFirebaseOptionSet.web;
      final r = await FirebaseInitializer(core).initialize(dev(), isWeb: true);
      expect(r.ready, isTrue);
      expect(core.initialised, isEmpty);
    });

    test('the active project is verified after initialisation', () async {
      final core = _FakeCore()..returnInstead = prodFirebaseOptionSet.web;
      final r = await FirebaseInitializer(core).initialize(dev(), isWeb: true);
      expect(r.errorCode, 'ENV_ACTIVE_PROJECT_MISMATCH');
    });

    test(
      'an initialisation failure is a safe error, not an exception',
      () async {
        final core = _FakeCore()..failWith = StateError('boom');
        final r = await FirebaseInitializer(
          core,
        ).initialize(dev(), isWeb: true);
        expect(r.errorCode, 'FIREBASE_INIT_FAILED');
      },
    );
  });

  group('the native registration files agree with the Dart options', () {
    test('dev Android google-services.json', () {
      final g =
          jsonDecode(
                File(
                  'config/firebase/dev/dev.google-services.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final info = g['project_info'] as Map<String, dynamic>;
      final client = (g['client'] as List).single as Map<String, dynamic>;
      final android = devFirebaseOptionSet.android;
      expect(info['project_id'], android.projectId);
      expect(info['project_number'], android.messagingSenderId);
      expect(info['storage_bucket'], android.storageBucket);
      expect((client['client_info'] as Map)['mobilesdk_app_id'], android.appId);
      expect(
        ((client['client_info'] as Map)['android_client_info']
            as Map)['package_name'],
        kApplicationId,
      );
      expect(
        ((client['api_key'] as List).first as Map)['current_key'],
        android.apiKey,
      );
    });

    test('dev iOS GoogleService-Info.plist', () {
      final text = File(
        'config/firebase/dev/dev.GoogleService-Info.plist',
      ).readAsStringSync();
      String value(String key) => RegExp(
        '<key>$key</key>\\s*<string>([^<]*)</string>',
      ).firstMatch(text)!.group(1)!;
      final ios = devFirebaseOptionSet.ios;
      expect(value('PROJECT_ID'), ios.projectId);
      expect(value('GCM_SENDER_ID'), ios.messagingSenderId);
      expect(value('GOOGLE_APP_ID'), ios.appId);
      expect(value('BUNDLE_ID'), kApplicationId);
      expect(value('BUNDLE_ID'), ios.iosBundleId);
      expect(value('STORAGE_BUCKET'), ios.storageBucket);
      expect(value('API_KEY'), ios.apiKey);
    });

    test('the Android and iOS identifiers match the native projects', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "$kApplicationId"'));
      expect(gradle, contains('namespace = "$kApplicationId"'));
      final pbx = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        RegExp(
          'PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(kApplicationId)};',
        ).allMatches(pbx).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('prod Android google-services.json', () {
      final g =
          jsonDecode(
                File(
                  'config/firebase/prod/prod.google-services.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final info = g['project_info'] as Map<String, dynamic>;
      final client = (g['client'] as List).single as Map<String, dynamic>;
      final android = prodFirebaseOptionSet.android;
      expect(info['project_id'], android.projectId);
      expect(info['project_id'], kProdFirebaseProjectId);
      expect(info['project_number'], android.messagingSenderId);
      expect(
        info['project_number'],
        prodFirebaseOptionSet.web.messagingSenderId,
      );
      expect(info['storage_bucket'], android.storageBucket);
      expect((client['client_info'] as Map)['mobilesdk_app_id'], android.appId);
      expect(
        ((client['client_info'] as Map)['android_client_info']
            as Map)['package_name'],
        kApplicationId,
      );
      expect(
        ((client['api_key'] as List).first as Map)['current_key'],
        android.apiKey,
      );
    });

    test('prod iOS GoogleService-Info.plist', () {
      final text = File(
        'config/firebase/prod/prod.GoogleService-Info.plist',
      ).readAsStringSync();
      String value(String key) => RegExp(
        '<key>$key</key>\\s*<string>([^<]*)</string>',
      ).firstMatch(text)!.group(1)!;
      final ios = prodFirebaseOptionSet.ios;
      expect(value('PROJECT_ID'), kProdFirebaseProjectId);
      expect(value('PROJECT_ID'), ios.projectId);
      expect(value('GCM_SENDER_ID'), ios.messagingSenderId);
      expect(value('GOOGLE_APP_ID'), ios.appId);
      expect(value('BUNDLE_ID'), kApplicationId);
      expect(value('BUNDLE_ID'), ios.iosBundleId);
      expect(value('STORAGE_BUCKET'), ios.storageBucket);
      expect(value('API_KEY'), ios.apiKey);
    });

    test('no native file of one environment names the other\'s project', () {
      for (final f in [
        'config/firebase/dev/dev.google-services.json',
        'config/firebase/dev/dev.GoogleService-Info.plist',
      ]) {
        expect(
          File(f).readAsStringSync(),
          isNot(contains(kProdFirebaseProjectId)),
        );
      }
      for (final f in [
        'config/firebase/prod/prod.google-services.json',
        'config/firebase/prod/prod.GoogleService-Info.plist',
      ]) {
        expect(
          File(f).readAsStringSync(),
          isNot(contains(kDevFirebaseProjectId)),
        );
      }
    });
  });
}
