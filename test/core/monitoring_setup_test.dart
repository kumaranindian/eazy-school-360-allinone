import 'package:eazy_school_360/core/logging/app_logger.dart';
import 'package:eazy_school_360/core/monitoring/monitoring_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planAppCheck', () {
    test('is off unless enabled', () {
      expect(
        planAppCheck(enabled: false, isWeb: true, webKey: 'k'),
        AppCheckPlan.off,
      );
    });
    test('web needs a site key', () {
      expect(
        planAppCheck(enabled: true, isWeb: true, webKey: '  '),
        AppCheckPlan.missingWebKey,
      );
      expect(
        planAppCheck(enabled: true, isWeb: true, webKey: 'k'),
        AppCheckPlan.activate,
      );
    });
    test('mobile needs no key', () {
      expect(
        planAppCheck(enabled: true, isWeb: false, webKey: ''),
        AppCheckPlan.activate,
      );
    });
  });

  test(
    'crashes are collected only in release builds on mobile, unless opted out',
    () {
      bool c({bool debug = false, bool web = false, bool out = false}) =>
          shouldCollectCrashes(isDebug: debug, isWeb: web, optedOut: out);
      expect(c(), isTrue);
      expect(c(debug: true), isFalse);
      expect(c(web: true), isFalse);
      expect(c(out: true), isFalse);
    },
  );

  test(
    'setUpMonitoring does nothing in tests (debug build, App Check off)',
    () async {
      await setUpMonitoring();
      expect(AppLogger.errorSink, isNull);
    },
  );

  group('AppLogger.errorSink', () {
    tearDown(() => AppLogger.errorSink = null);

    test('receives errors only, and a throwing sink is contained', () {
      final seen = <String>[];
      AppLogger.errorSink = (m, e, s) => seen.add(m);
      AppLogger.warning('w');
      AppLogger.error('boom', error: StateError('x'));
      expect(seen, ['boom']);
      AppLogger.errorSink = (m, e, s) => throw StateError('sink broke');
      AppLogger.error('still fine');
    });
  });
}
