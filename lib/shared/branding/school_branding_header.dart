import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'branch_switcher.dart';
import 'brand_logo.dart';
import 'school_brand_logo.dart';
import 'school_branding.dart';

/// The one branding layout of the signed-in area:
///
/// ```
/// [school logo]          [ title ]          [app logo] [actions…]
/// ```
///
/// * The title is centred on the **bar**, not on the space left between the
///   side groups, so it does not drift when the two sides differ in width
///   (a plain `Row` with `spaceBetween` would). When the side groups leave too
///   little room to centre it without touching them, it is centred in the
///   free space between them instead — never overlapping, never clipped.
/// * Both logos are square, keep their aspect ratio and are sized from the
///   available width, not hard-coded per screen.
/// * Long titles end in an ellipsis; text scaling is honoured.
///
/// The widget draws no background: it is meant to be the `title` of an
/// `AppBar` (see [SchoolBrandingAppBar]) or to sit in any bar-like surface.
class SchoolBrandingHeader extends StatelessWidget {
  /// The school's logo (or its initial). Left corner.
  final Widget schoolLogo;

  /// The EazySchool mark. Right corner, before [actions].
  final Widget appLogo;

  /// Centre text: the school name on the dashboard, the screen title elsewhere.
  final String title;

  /// Optional second line under [title] (kept short; hidden on narrow bars).
  final String? subtitle;

  /// Optional widget before the school logo (a back or menu button).
  final Widget? leading;

  /// Controls after the app logo (notifications, sign out…).
  final List<Widget> actions;

  /// Space between a side group and the title.
  final double gap;

  /// Below this width the title is no longer forced to the bar's centre.
  final double minCenteredTitleWidth;

  const SchoolBrandingHeader({
    super.key,
    required this.schoolLogo,
    required this.appLogo,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.gap = 12,
    this.minCenteredTitleWidth = 72,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSubtitle =
        subtitle != null &&
        subtitle!.isNotEmpty &&
        MediaQuery.sizeOf(context).width >= 600;
    return CustomMultiChildLayout(
      delegate: _HeaderLayout(
        gap: gap,
        minCenteredTitleWidth: minCenteredTitleWidth,
      ),
      children: [
        LayoutId(
          id: _Slot.left,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [if (leading != null) leading!, schoolLogo],
          ),
        ),
        LayoutId(
          id: _Slot.title,
          child: Semantics(
            header: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (showSubtitle)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        LayoutId(
          id: _Slot.right,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [appLogo, ...actions],
          ),
        ),
      ],
    );
  }
}

enum _Slot { left, title, right }

class _HeaderLayout extends MultiChildLayoutDelegate {
  final double gap;
  final double minCenteredTitleWidth;

  _HeaderLayout({required this.gap, required this.minCenteredTitleWidth});

  @override
  void performLayout(Size size) {
    final w = size.width;
    final h = size.height;
    // Side groups at their natural size, but never so wide that the title
    // loses all its room.
    final sideMax = ((w - minCenteredTitleWidth) / 2).clamp(0.0, w);
    final left = layoutChild(
      _Slot.left,
      BoxConstraints(maxWidth: sideMax, maxHeight: h),
    );
    final right = layoutChild(
      _Slot.right,
      BoxConstraints(maxWidth: w - left.width - gap, maxHeight: h),
    );
    positionChild(_Slot.left, Offset(0, (h - left.height) / 2));
    positionChild(_Slot.right, Offset(w - right.width, (h - right.height) / 2));

    final inset = (left.width > right.width ? left.width : right.width) + gap;
    final centeredMax = w - 2 * inset;
    final double maxTitle;
    final bool centerOnBar = centeredMax >= minCenteredTitleWidth;
    if (centerOnBar) {
      maxTitle = centeredMax;
    } else {
      maxTitle = (w - left.width - right.width - 2 * gap).clamp(0.0, w);
    }
    final t = layoutChild(
      _Slot.title,
      BoxConstraints(maxWidth: maxTitle, maxHeight: h),
    );
    final double x;
    if (centerOnBar) {
      x = (w - t.width) / 2;
    } else {
      final free = w - left.width - right.width - 2 * gap;
      x = left.width + gap + (free - t.width) / 2;
    }
    positionChild(_Slot.title, Offset(x, (h - t.height) / 2));
  }

  @override
  bool shouldRelayout(_HeaderLayout old) =>
      old.gap != gap || old.minCenteredTitleWidth != minCenteredTitleWidth;
}

/// The signed-in area's top bar: [SchoolBrandingHeader] fed from the current
/// tenant ([schoolBrandingProvider] — already resolved with the sign-in, so no
/// extra read per screen) inside a standard `AppBar`, keeping the usual
/// height, status-bar and safe-area handling.
///
/// [screenTitle] is the centre text; when null the school's name is shown
/// (dashboard). The school name is never shown *and* repeated as a title.
class SchoolBrandingAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  final String? screenTitle;

  /// Product name used before a school is known (and as the logo label).
  final String fallbackTitle;
  final List<Widget> actions;

  const SchoolBrandingAppBar({
    super.key,
    this.screenTitle,
    this.fallbackTitle = 'EazySchool 360',
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final branding = ref.watch(schoolBrandingProvider);
    final schoolName = branding?.name.trim() ?? '';
    final title = (screenTitle != null && screenTitle!.isNotEmpty)
        ? screenTitle!
        : (schoolName.isNotEmpty ? schoolName : fallbackTitle);
    final width = MediaQuery.sizeOf(context).width;
    final logo = width < 600 ? 32.0 : 36.0;

    final Widget schoolLogo = branding == null
        // Nothing known yet (first frame of a sign-in): reserve the slot so the
        // bar does not jump when the school arrives.
        ? SizedBox(width: logo, height: logo)
        : SchoolLogoImage(
            url: branding.logoUrl,
            label: branding.name,
            size: logo,
            fallbackChild: SchoolInitialBadge(name: branding.name, size: logo),
          );

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      titleSpacing: 12,
      centerTitle: false,
      // The AppBar offers its title unbounded height; the header needs a
      // definite one (the toolbar's) to centre its three slots vertically.
      title: SizedBox(
        height: kToolbarHeight,
        child: SchoolBrandingHeader(
          schoolLogo: schoolLogo,
          appLogo: BrandMark(size: logo),
          title: title,
          actions: [const BranchSwitcher(), ...actions],
        ),
      ),
    );
  }
}
