import 'package:flutter/material.dart';

/// Tells the screens below the shell that a [PageHero] is already showing
/// this screen's title — so a root screen should not draw a second header.
///
/// Only set while the current route is a top-level root; screens pushed on
/// top (forms, details) are not under an active scope and keep their app
/// bar with the back button.
class HeroScope extends InheritedWidget {
  final bool active;

  const HeroScope({super.key, required this.active, required super.child});

  /// Whether the nearest shell is currently showing a hero.
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeroScope>()?.active ?? false;

  @override
  bool updateShouldNotify(HeroScope oldWidget) => oldWidget.active != active;
}

/// An app bar for a screen that is BOTH a top-level root and a pushed page:
///
/// - as a root (hero showing): no title bar. If the screen has [actions]
///   (notifications, insights, mark-all-read…) they stay available in a
///   slim bar under the hero instead of being lost.
/// - otherwise: the normal navy app bar with [title] and back button.
PreferredSizeWidget? pageAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
}) {
  if (!HeroScope.isActive(context)) {
    return AppBar(title: title, actions: actions);
  }
  if (actions == null || actions.isEmpty) return null;
  final scheme = Theme.of(context).colorScheme;
  return AppBar(
    toolbarHeight: 44,
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    foregroundColor: scheme.onSurface,
    iconTheme: IconThemeData(color: scheme.onSurface),
    actionsIconTheme: IconThemeData(color: scheme.onSurface),
    shape: const Border(),
    actions: actions,
  );
}
