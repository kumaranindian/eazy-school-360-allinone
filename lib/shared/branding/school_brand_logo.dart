import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import 'brand_logo.dart';
import 'school_branding.dart';

/// A school logo that never breaks the layout: it reserves a fixed square
/// while loading, keeps the picture's aspect ratio (no crop, no stretch), and
/// shows the EazySchool mark when there is no logo, the URL is dead, or the
/// network fails.
class SchoolLogoImage extends StatelessWidget {
  final String? url;

  /// Accessibility label — normally the school's name.
  final String label;
  final double size;
  final bool onDark;

  /// Shown when there is no logo or it cannot be loaded. Defaults to the
  /// EazySchool mark; a slot that sits beside that mark passes its own so the
  /// product mark is never shown twice.
  final Widget? fallbackChild;

  const SchoolLogoImage({
    super.key,
    required this.url,
    required this.label,
    this.size = 32,
    this.onDark = false,
    this.fallbackChild,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackChild ?? BrandMark(size: size, onDark: onDark);
    final logoUrl = usableLogoUrl(url);
    if (logoUrl == null) return fallback;

    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.22);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A neutral plate so a transparent PNG stays legible on the navy
          // hero and in dark mode.
          color: scheme.surface,
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(size * 0.06),
            child: Image.network(
              logoUrl,
              // A replaced logo gets a new URL; the key makes sure the old
              // image state is not reused.
              key: ValueKey(logoUrl),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              semanticLabel: label,
              // On the web the image is normally fetched with XHR, which a
              // bucket without CORS headers blocks. Falling back to a plain
              // <img> element needs no CORS and still shows the logo.
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const SizedBox.expand(),
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in school's logo, or the EazySchool mark when the school has
/// none (or nobody is signed in).
class SchoolBrandLogo extends ConsumerWidget {
  final double size;
  final bool onDark;

  const SchoolBrandLogo({super.key, this.size = 32, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(schoolBrandingProvider);
    return SchoolLogoImage(
      url: branding?.logoUrl,
      label: branding?.name ?? 'EazySchool 360',
      size: size,
      onDark: onDark,
    );
  }
}

/// The school's logo and the EazySchool mark side by side: tenant identity
/// first, product identity second. A school without a logo shows only the
/// EazySchool mark (never the same mark twice).
class SchoolAndProductMarks extends ConsumerWidget {
  final double size;
  final bool onDark;

  const SchoolAndProductMarks({super.key, this.size = 32, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(schoolBrandingProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (branding != null && branding.hasLogo) ...[
          SchoolLogoImage(
            url: branding.logoUrl,
            label: branding.name,
            size: size,
            onDark: onDark,
            fallbackChild: SchoolInitialBadge(name: branding.name, size: size),
          ),
          SizedBox(width: size * 0.25),
        ],
        BrandMark(size: size, onDark: onDark),
      ],
    );
  }
}

/// A school-specific placeholder (its first letter) for when the logo cannot
/// be shown, so the slot is still recognisably the school's, not the product's.
class SchoolInitialBadge extends StatelessWidget {
  final String name;
  final double size;

  const SchoolInitialBadge({super.key, required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// "Powered by EazySchool 360" with the product mark: the product's quiet
/// attribution next to school-branded surfaces.
class PoweredByEazySchool extends StatelessWidget {
  /// Text appended after the product name (a version line, for example).
  final String? suffix;

  const PoweredByEazySchool({super.key, this.suffix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = [
      'Powered by EazySchool 360',
      if (suffix != null && suffix!.isNotEmpty) suffix!,
    ].join(' · ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 14),
        const SizedBox(width: AppSpacing.xs + 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
