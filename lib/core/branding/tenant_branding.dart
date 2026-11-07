import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../theme/color_math.dart';

/// Tenant-wide branding (docs/tenant-theme.md): ONE configuration per school,
/// shared by every role and branch of that school. Pure Dart — the stored
/// shapes, the readable-colour rules (mirrored by `functions/branding.js`) and
/// the resolver that turns "what is stored" into "what the app paints".

/// The seven colours a school can set. Status colours (success / warning /
/// error) are deliberately not among them.
enum BrandToken {
  primary,
  secondary,
  accent,
  surface,
  background,
  text,
  selectedNav;

  String get label => switch (this) {
    primary => 'Primary',
    secondary => 'Secondary',
    accent => 'Accent',
    surface => 'Surface',
    background => 'Background',
    text => 'Text',
    selectedNav => 'Selected navigation',
  };
}

enum BrandingAppearance {
  system,
  light,
  dark;

  String get wire => name;

  String get label => switch (this) {
    system => 'Follow the device',
    light => 'Always light',
    dark => 'Always dark',
  };

  static BrandingAppearance parse(Object? raw) =>
      BrandingAppearance.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => BrandingAppearance.system,
      );
}

/// A complete colour set.
@immutable
class BrandColors {
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color surface;
  final Color background;
  final Color text;
  final Color selectedNav;

  const BrandColors({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.surface,
    required this.background,
    required this.text,
    required this.selectedNav,
  });

  /// The approved neutral/green design system (the default).
  static const BrandColors emerald = BrandColors(
    primary: Color(0xFF16856A),
    secondary: Color(0xFF527A69),
    accent: Color(0xFFE0A030),
    surface: Color(0xFFFFFFFF),
    background: Color(0xFFF7F8F7),
    text: Color(0xFF17231F),
    selectedNav: Color(0xFF16856A),
  );

  Color of(BrandToken t) => switch (t) {
    BrandToken.primary => primary,
    BrandToken.secondary => secondary,
    BrandToken.accent => accent,
    BrandToken.surface => surface,
    BrandToken.background => background,
    BrandToken.text => text,
    BrandToken.selectedNav => selectedNav,
  };

  BrandColors with_(BrandToken t, Color c) => BrandColors(
    primary: t == BrandToken.primary ? c : primary,
    secondary: t == BrandToken.secondary ? c : secondary,
    accent: t == BrandToken.accent ? c : accent,
    surface: t == BrandToken.surface ? c : surface,
    background: t == BrandToken.background ? c : background,
    text: t == BrandToken.text ? c : text,
    selectedNav: t == BrandToken.selectedNav ? c : selectedNav,
  );

  /// A stored colour map, or null unless all seven are valid "#RRGGBB".
  static BrandColors? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final c = <BrandToken, Color>{};
    for (final t in BrandToken.values) {
      final v = ColorMath.parse(raw[t.name]);
      if (v == null) return null;
      c[t] = v;
    }
    return BrandColors(
      primary: c[BrandToken.primary]!,
      secondary: c[BrandToken.secondary]!,
      accent: c[BrandToken.accent]!,
      surface: c[BrandToken.surface]!,
      background: c[BrandToken.background]!,
      text: c[BrandToken.text]!,
      selectedNav: c[BrandToken.selectedNav]!,
    );
  }

  Map<String, String> toMap() => {
    for (final t in BrandToken.values) t.name: ColorMath.hex(of(t)),
  };

  /// Readability problems, by token (empty = fine). The same rules as the
  /// server, so the editor can warn before saving and the app can fall back
  /// when a stored set is unreadable.
  Map<BrandToken, String> problems() {
    final out = <BrandToken, String>{};
    void need(BrandToken fg, Color bg, double min, String what) {
      final r = ColorMath.contrast(of(fg), bg);
      if (r < min) {
        out[fg] = '$what is ${r.toStringAsFixed(1)}:1, needs $min:1';
      }
    }

    need(BrandToken.text, surface, 4.5, 'Text on surface');
    need(BrandToken.text, background, 4.5, 'Text on background');
    need(BrandToken.secondary, surface, 3, 'Secondary on surface');
    // A highlight colour: never the only carrier of text, and the approved
    // default gold is 2.3:1, so it is held to a lower bar.
    need(BrandToken.accent, surface, 2, 'Accent on surface');
    need(BrandToken.selectedNav, surface, 3, 'Selected navigation on surface');
    return out;
  }

  bool get isReadable => problems().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is BrandColors &&
      [for (final t in BrandToken.values) of(t)].toString() ==
          [for (final t in BrandToken.values) other.of(t)].toString();

  @override
  int get hashCode =>
      Object.hashAll([for (final t in BrandToken.values) of(t)]);
}

@immutable
class BrandPreset {
  final String id;
  final String label;
  final BrandColors colors;
  const BrandPreset(this.id, this.label, this.colors);
}

/// Built-in presets (same values as `functions/branding.js`).
abstract final class BrandPresets {
  static const String defaultId = 'emerald';

  static const List<BrandPreset> builtIn = [
    BrandPreset('emerald', 'Emerald', BrandColors.emerald),
    BrandPreset(
      'indigo',
      'Indigo',
      BrandColors(
        primary: Color(0xFF4F46A5),
        secondary: Color(0xFF5B6275),
        accent: Color(0xFFD08A1E),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFF6F6FA),
        text: Color(0xFF1B1B2F),
        selectedNav: Color(0xFF4F46A5),
      ),
    ),
    BrandPreset(
      'crimson',
      'Crimson',
      BrandColors(
        primary: Color(0xFFB23A48),
        secondary: Color(0xFF6D5A5E),
        accent: Color(0xFFC98A1B),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFFAF6F6),
        text: Color(0xFF2A1A1D),
        selectedNav: Color(0xFFB23A48),
      ),
    ),
    BrandPreset(
      'amber',
      'Amber',
      BrandColors(
        primary: Color(0xFF9A5B00),
        secondary: Color(0xFF6B5E48),
        accent: Color(0xFF2A7F62),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFFAF8F3),
        text: Color(0xFF2B2214),
        selectedNav: Color(0xFF9A5B00),
      ),
    ),
    BrandPreset(
      'plum',
      'Plum',
      BrandColors(
        primary: Color(0xFF7A3E8E),
        secondary: Color(0xFF665A70),
        accent: Color(0xFFC98A1B),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFF9F6FA),
        text: Color(0xFF241A28),
        selectedNav: Color(0xFF7A3E8E),
      ),
    ),
    BrandPreset(
      'graphite',
      'Graphite',
      BrandColors(
        primary: Color(0xFF3D4A52),
        secondary: Color(0xFF5F6B72),
        accent: Color(0xFFC98A1B),
        surface: Color(0xFFFFFFFF),
        background: Color(0xFFF5F6F7),
        text: Color(0xFF171C1F),
        selectedNav: Color(0xFF3D4A52),
      ),
    ),
  ];
}

/// `platformBranding/default`: the fallback for schools without their own
/// theme, plus the platform's custom presets.
@immutable
class PlatformBranding {
  final int version;
  final String defaultPreset;
  final List<BrandPreset> customPresets;

  const PlatformBranding({
    this.version = 0,
    this.defaultPreset = BrandPresets.defaultId,
    this.customPresets = const [],
  });

  static const PlatformBranding builtIn = PlatformBranding();

  /// Built-in plus custom presets; a built-in id cannot be replaced.
  List<BrandPreset> get presets => [
    ...BrandPresets.builtIn,
    for (final p in customPresets)
      if (!BrandPresets.builtIn.any((b) => b.id == p.id)) p,
  ];

  BrandPreset presetById(String? id) => presets.firstWhere(
    (p) => p.id == id,
    orElse: () => BrandPresets.builtIn.first,
  );

  /// The colours of the default preset (always readable: an unreadable
  /// custom default falls back to the built-in one).
  BrandColors get defaultColors {
    final c = presetById(defaultPreset).colors;
    return c.isReadable ? c : BrandColors.emerald;
  }

  static PlatformBranding fromMap(Map<String, dynamic>? data) {
    if (data == null) return builtIn;
    final custom = <BrandPreset>[];
    final raw = data['presets'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) continue;
        final colors = BrandColors.fromMap(v['colors']);
        final label = v['label'];
        if (colors != null && label is String && label.trim().isNotEmpty) {
          custom.add(BrandPreset(e.key as String, label, colors));
        }
      }
    }
    final version = data['version'];
    return PlatformBranding(
      version: version is int ? version : 0,
      defaultPreset: data['defaultPreset'] is String
          ? data['defaultPreset'] as String
          : BrandPresets.defaultId,
      customPresets: custom,
    );
  }

  Map<String, dynamic> toMap() => {
    'version': version,
    'defaultPreset': defaultPreset,
    'presets': {
      for (final p in customPresets)
        p.id: {'label': p.label, 'colors': p.colors.toMap()},
    },
  };
}

/// `schools/{s}/branding/config`. `colors == null` means "use the platform
/// default" (a school that never customised, or reset).
@immutable
class TenantBranding {
  final String schoolId;
  final int version;
  final String? presetId;
  final BrandColors? colors;
  final BrandingAppearance appearance;

  const TenantBranding({
    required this.schoolId,
    this.version = 0,
    this.presetId,
    this.colors,
    this.appearance = BrandingAppearance.system,
  });

  bool get isDefault => colors == null;

  /// Null when the stored document is not for [expectedSchoolId] — a branding
  /// document of another school is never applied.
  static TenantBranding? fromMap(
    Map<String, dynamic>? data, {
    required String expectedSchoolId,
  }) {
    if (data == null) return null;
    if (data['schoolId'] != expectedSchoolId) return null;
    final v = data['version'];
    return TenantBranding(
      schoolId: expectedSchoolId,
      version: v is int ? v : 0,
      presetId: data['preset'] is String ? data['preset'] as String : null,
      colors: BrandColors.fromMap(data['colors']),
      appearance: BrandingAppearance.parse(data['appearance']),
    );
  }

  Map<String, dynamic> toMap() => {
    'schoolId': schoolId,
    'version': version,
    'preset': presetId,
    'colors': colors?.toMap(),
    'appearance': appearance.wire,
  };
}

/// What the app paints with.
@immutable
class ResolvedTheme {
  /// The school this theme belongs to; null for the platform default shown
  /// signed out or between accounts.
  final String? schoolId;
  final int version;
  final BrandColors colors;
  final BrandingAppearance appearance;
  final String presetId;

  const ResolvedTheme({
    required this.schoolId,
    required this.version,
    required this.colors,
    required this.appearance,
    required this.presetId,
  });

  static const ResolvedTheme platformDefault = ResolvedTheme(
    schoolId: null,
    version: 0,
    colors: BrandColors.emerald,
    appearance: BrandingAppearance.system,
    presetId: BrandPresets.defaultId,
  );

  bool get isDefaultColors => colors == BrandColors.emerald;

  @override
  bool operator ==(Object other) =>
      other is ResolvedTheme &&
      other.schoolId == schoolId &&
      other.version == version &&
      other.colors == colors &&
      other.appearance == appearance &&
      other.presetId == presetId;

  @override
  int get hashCode =>
      Object.hash(schoolId, version, colors, appearance, presetId);
}

abstract final class BrandingResolver {
  /// The theme for [school] over [platform]. A school's colours are used
  /// token by token: any that fail the readability rules are replaced by the
  /// default's (and if the set is still unreadable, the default is used whole)
  /// — a school can never make the app unreadable.
  static ResolvedTheme resolve({
    required String? schoolId,
    TenantBranding? school,
    PlatformBranding platform = PlatformBranding.builtIn,
  }) {
    final base = platform.defaultColors;
    final own = (school != null && school.schoolId == schoolId) ? school : null;
    var colors = base;
    var preset = platform.defaultPreset;
    if (own != null && own.colors != null) {
      colors = own.colors!;
      for (final t in colors.problems().keys) {
        colors = colors.with_(t, base.of(t));
      }
      if (!colors.isReadable) colors = base;
      preset = own.presetId ?? preset;
    }
    return ResolvedTheme(
      schoolId: schoolId,
      version: own?.version ?? 0,
      colors: colors,
      appearance: own?.appearance ?? BrandingAppearance.system,
      presetId: preset,
    );
  }
}
