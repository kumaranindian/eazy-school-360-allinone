import 'package:flutter/material.dart';

/// Paths of the bundled brand artwork (see `assets/brand/`). The `_dark`
/// variants carry white lettering for navy surfaces.
abstract final class BrandAssets {
  static const logoFull = 'assets/brand/logo_full.png';
  static const logoFullDark = 'assets/brand/logo_full_dark.png';
  static const logoMark = 'assets/brand/logo_mark.png';
  static const logoMarkDark = 'assets/brand/logo_mark_dark.png';

  /// Decode the artwork once at start-up so the first screen that shows it
  /// never flashes an empty box. Cheap: four small PNGs.
  static Future<void> precache(BuildContext context) async {
    for (final path in const [logoFull, logoFullDark, logoMark, logoMarkDark]) {
      if (!context.mounted) return;
      await precacheImage(AssetImage(path), context);
    }
  }
}

/// Which artwork to use: by default it follows the ambient brightness, but a
/// logo placed on an always-dark panel passes [onDark] explicitly.
bool _useDark(BuildContext context, bool? onDark) =>
    onDark ?? Theme.of(context).brightness == Brightness.dark;

/// The full EazySchool 360 lockup (cap + "E" + wordmark + 360 ring).
class BrandLogo extends StatelessWidget {
  final double height;
  final bool? onDark;

  const BrandLogo({super.key, this.height = 48, this.onDark});

  @override
  Widget build(BuildContext context) {
    final dark = _useDark(context, onDark);
    // The artwork is already pre-sized (720px wide), so it is decoded at its
    // native size: that way it shares the cache entry that
    // [BrandAssets.precache] warmed instead of decoding a second copy.
    final image = Image.asset(
      dark ? BrandAssets.logoFullDark : BrandAssets.logoFull,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: 'EazySchool 360',
    );
    // The dark lockup is a navy rectangle; round it so it sits on a dark
    // page as a badge, not a box.
    return dark
        ? ClipRRect(
            borderRadius: BorderRadius.circular(height * 0.14),
            child: image,
          )
        : image;
  }
}

/// The square cap-and-"E" mark, for tight spaces (app bar, rail, splash).
class BrandMark extends StatelessWidget {
  final double size;
  final bool? onDark;

  const BrandMark({super.key, this.size = 32, this.onDark});

  @override
  Widget build(BuildContext context) {
    final dark = _useDark(context, onDark);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        dark ? BrandAssets.logoMarkDark : BrandAssets.logoMark,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        semanticLabel: 'EazySchool 360',
      ),
    );
  }
}
