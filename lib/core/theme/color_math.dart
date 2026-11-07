import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colour arithmetic shared by the tenant theme (contrast checks, tints). Pure.
abstract final class ColorMath {
  /// WCAG relative luminance, 0..1.
  static double luminance(Color c) {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  }

  /// WCAG contrast ratio, 1..21.
  static double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// White or near-black, whichever reads better on [c].
  static Color onColor(Color c) {
    const dark = Color(0xFF111111);
    return contrast(Colors.white, c) >= contrast(dark, c) ? Colors.white : dark;
  }

  /// [a] with [t] (0..1) of [b] mixed in.
  static Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  /// Moves [c] toward white until it reaches [min] contrast on [bg] (dark
  /// surfaces need lighter brand colours).
  static Color liftOn(Color c, Color bg, double min) {
    var out = c;
    for (var i = 0; i < 20 && contrast(out, bg) < min; i++) {
      out = mix(out, Colors.white, 0.1);
    }
    return out;
  }

  /// "#RRGGBB" (upper-case), the stored form.
  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// A stored "#RRGGBB" colour, or null when it is not one.
  static Color? parse(Object? raw) {
    if (raw is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) {
      return null;
    }
    return Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
  }
}
