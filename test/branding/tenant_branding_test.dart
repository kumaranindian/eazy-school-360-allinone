import 'dart:io';

import 'package:eazy_school_360/core/theme/color_math.dart';
import 'package:eazy_school_360/core/branding/tenant_branding.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every built-in preset is readable', () {
    for (final p in BrandPresets.builtIn) {
      expect(p.colors.problems(), isEmpty, reason: p.id);
    }
  });

  test('Dart presets match functions/branding.js (no drift)', () {
    final js = File('functions/branding.js').readAsStringSync();
    for (final p in BrandPresets.builtIn) {
      final m = RegExp(
        '${p.id}: \\{ label: \'(\\w+)\', colors: \\{([^}]*)\\}',
      ).firstMatch(js);
      expect(m, isNotNull, reason: p.id);
      expect(m!.group(1), p.label);
      final server = {
        for (final e in RegExp(
          "(\\w+): '(#[0-9A-F]{6})'",
        ).allMatches(m.group(2)!))
          e.group(1)!: e.group(2)!,
      };
      expect(server, p.colors.toMap(), reason: p.id);
    }
  });

  test('contrast maths: black on white is 21, same colour is 1', () {
    expect(
      ColorMath.contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      ColorMath.contrast(const Color(0xFF123456), const Color(0xFF123456)),
      closeTo(1, 0.001),
    );
  });

  test('hex round trip and parsing', () {
    expect(ColorMath.hex(const Color(0xFF16856A)), '#16856A');
    expect(ColorMath.parse('#16856a'), const Color(0xFF16856A));
    expect(ColorMath.parse('red'), isNull);
    expect(ColorMath.parse('#12345'), isNull);
    expect(ColorMath.parse(null), isNull);
  });

  test('unreadable sets are reported per token', () {
    final bad = BrandColors.emerald
        .with_(BrandToken.text, const Color(0xFFCCCCCC))
        .with_(BrandToken.secondary, const Color(0xFFEEEEEE));
    expect(
      bad.problems().keys,
      containsAll([BrandToken.text, BrandToken.secondary]),
    );
    expect(bad.isReadable, isFalse);
  });

  test('a stored colour map needs all seven valid colours', () {
    final map = BrandColors.emerald.toMap();
    expect(BrandColors.fromMap(map), BrandColors.emerald);
    expect(BrandColors.fromMap({...map, 'text': 'nope'}), isNull);
    expect(BrandColors.fromMap({...map}..remove('accent')), isNull);
    expect(BrandColors.fromMap(null), isNull);
  });

  group('resolver', () {
    final indigo = BrandPresets.builtIn[1].colors;

    test('a school without branding gets the platform default', () {
      final r = BrandingResolver.resolve(schoolId: 'a');
      expect(r.colors, BrandColors.emerald);
      expect(r.appearance, BrandingAppearance.system);
    });

    test('a school with colours gets them', () {
      final r = BrandingResolver.resolve(
        schoolId: 'a',
        school: TenantBranding(
          schoolId: 'a',
          version: 3,
          presetId: 'indigo',
          colors: indigo,
          appearance: BrandingAppearance.light,
        ),
      );
      expect(r.colors, indigo);
      expect(r.version, 3);
      expect(r.appearance, BrandingAppearance.light);
    });

    test("another school's branding is never applied", () {
      final r = BrandingResolver.resolve(
        schoolId: 'a',
        school: TenantBranding(schoolId: 'b', version: 9, colors: indigo),
      );
      expect(r.colors, BrandColors.emerald);
      expect(r.version, 0);
    });

    test('unreadable stored colours fall back token by token', () {
      final bad = indigo.with_(BrandToken.text, const Color(0xFFDDDDDD));
      final r = BrandingResolver.resolve(
        schoolId: 'a',
        school: TenantBranding(schoolId: 'a', version: 1, colors: bad),
      );
      expect(r.colors.text, BrandColors.emerald.text);
      expect(r.colors.primary, indigo.primary);
      expect(r.colors.isReadable, isTrue);
    });

    test(
      'a platform default other than emerald applies to unbranded schools',
      () {
        final r = BrandingResolver.resolve(
          schoolId: 'a',
          platform: const PlatformBranding(defaultPreset: 'plum'),
        );
        expect(r.colors, BrandPresets.builtIn[4].colors);
      },
    );

    test('reset (colors null) returns to the platform default', () {
      final r = BrandingResolver.resolve(
        schoolId: 'a',
        school: const TenantBranding(schoolId: 'a', version: 5),
      );
      expect(r.colors, BrandColors.emerald);
      expect(r.version, 5);
    });
  });

  group('stored documents', () {
    test('tenant branding for the wrong school is rejected', () {
      expect(
        TenantBranding.fromMap({
          'schoolId': 'b',
          'version': 1,
        }, expectedSchoolId: 'a'),
        isNull,
      );
    });

    test('round trip', () {
      final t = TenantBranding(
        schoolId: 'a',
        version: 2,
        presetId: 'indigo',
        colors: BrandPresets.builtIn[1].colors,
        appearance: BrandingAppearance.dark,
      );
      final back = TenantBranding.fromMap(t.toMap(), expectedSchoolId: 'a')!;
      expect(back.version, 2);
      expect(back.colors, t.colors);
      expect(back.appearance, BrandingAppearance.dark);
    });

    test('platform branding: custom presets load, bad ones are skipped', () {
      final p = PlatformBranding.fromMap({
        'version': 4,
        'defaultPreset': 'teal2',
        'presets': {
          'teal2': {'label': 'Teal', 'colors': BrandColors.emerald.toMap()},
          'broken': {
            'label': 'x',
            'colors': {'primary': 'nope'},
          },
          'emerald': {'label': 'Hijack', 'colors': BrandColors.emerald.toMap()},
        },
      });
      expect(p.version, 4);
      expect(p.presets.map((e) => e.id), contains('teal2'));
      expect(p.presets.map((e) => e.id), isNot(contains('broken')));
      expect(p.presets.where((e) => e.id == 'emerald').single.label, 'Emerald');
      expect(p.defaultPreset, 'teal2');
    });
  });
}
