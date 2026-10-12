import 'package:eazy_school_360/core/utils/responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenSizeForWidth', () {
    test('returns mobile below the mobile breakpoint', () {
      expect(screenSizeForWidth(320), ScreenSize.mobile);
      expect(screenSizeForWidth(599), ScreenSize.mobile);
    });

    test('returns tablet between breakpoints', () {
      expect(screenSizeForWidth(600), ScreenSize.tablet);
      expect(screenSizeForWidth(1023), ScreenSize.tablet);
    });

    test('returns desktop at/above the desktop breakpoint', () {
      expect(screenSizeForWidth(1024), ScreenSize.desktop);
      expect(screenSizeForWidth(1920), ScreenSize.desktop);
    });
  });
}
