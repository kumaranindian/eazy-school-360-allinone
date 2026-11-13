import 'package:flutter/material.dart';

import '../../../../../core/theme/admin_dashboard_palette.dart';

/// Presentation pieces shared by the Parents list, the Parent details and the
/// Parent login-access screens. Pure UI: data and callbacks come in; colours
/// come from [AdminDashboardPalette] (the approved light design tokens).

/// The white page title row under the shared app header: back arrow, title
/// and optional trailing action (e.g. the edit pencil).
class ParentsPageBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const ParentsPageBar({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return Material(
      color: p.card,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, color: p.textPrimary),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// The compact blue-tinted heading of a list ("Parents & Guardians").
class ParentsHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const ParentsHeading({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AdminDashboardPalette.radius),
        border: Border.all(color: p.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The white rounded surface of a block (shadow outside the surface).
class ParentsCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const ParentsCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final radius = BorderRadius.circular(AdminDashboardPalette.radius);
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A section title inside a card: icon, bold title, optional trailing badge.
class ParentsSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Color? color;

  const ParentsSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return Row(
      children: [
        Icon(icon, color: color ?? p.primary, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

enum ParentsTone { success, neutral, warning, danger }

/// A small rounded status pill ("Active", "Enabled", "Activated").
class ParentsBadge extends StatelessWidget {
  final String label;
  final ParentsTone tone;
  const ParentsBadge(this.label, {super.key, this.tone = ParentsTone.success});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final color = switch (tone) {
      ParentsTone.success => p.success,
      ParentsTone.warning => p.warning,
      ParentsTone.neutral => p.textSecondary,
      ParentsTone.danger => Theme.of(context).colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A round avatar: the photo when there is one, else the initials on a
/// colour taken from the name (the same name always gets the same colour).
class ParentsAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const ParentsAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 48,
  });

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Color _colorFor(AdminDashboardPalette p) {
    final options = [p.primary, p.purple, p.teal, p.success, p.warning];
    final h = name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
    return options[h % options.length];
  }

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final color = _colorFor(p);
    final url = photoUrl;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: color,
        backgroundImage: url != null && url.isNotEmpty
            ? NetworkImage(url)
            : null,
        child: url != null && url.isNotEmpty
            ? null
            : Text(
                initialsOf(name),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.36,
                ),
              ),
      ),
    );
  }
}

/// icon + text line used for phone, email and similar facts.
class ParentsFactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? label;
  final Color? valueColor;
  final bool bold;

  const ParentsFactRow({
    super.key,
    required this.icon,
    required this.text,
    this.label,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                Text(
                  text,
                  style: t.bodyLarge?.copyWith(
                    color: valueColor ?? p.textPrimary,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One parent in the list: avatar, name + status, phone, email, "Has login",
/// optional leading checkbox (selection mode) and trailing actions.
class ParentListCard extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String phone;
  final String? email;
  final bool active;
  final bool hasLogin;
  final VoidCallback onTap;
  final Widget? leading;
  final List<Widget> actions;

  const ParentListCard({
    super.key,
    required this.name,
    required this.phone,
    required this.active,
    required this.hasLogin,
    required this.onTap,
    this.photoUrl,
    this.email,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return ParentsCard(
      onTap: onTap,
      semanticLabel:
          '$name, ${active ? 'active' : 'inactive'}'
          '${hasLogin ? ', has login' : ''}',
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) leading!,
          ParentsAvatar(name: name, photoUrl: photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: t.titleMedium?.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    ParentsBadge(
                      active ? 'Active' : 'Inactive',
                      tone: active ? ParentsTone.success : ParentsTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (phone.isNotEmpty)
                  _line(context, Icons.phone_outlined, phone),
                if (email != null && email!.isNotEmpty)
                  _line(context, Icons.mail_outline, email!),
                if (hasLogin)
                  _line(context, Icons.vpn_key_outlined, 'Has login'),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_right, color: p.textSecondary),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final p = AdminDashboardPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A linked child on the parent's details: avatar, name, admission number and
/// status.
class ParentsChildCard extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String admissionNumber;
  final String statusLabel;
  final bool active;
  final VoidCallback onTap;

  const ParentsChildCard({
    super.key,
    required this.name,
    required this.admissionNumber,
    required this.statusLabel,
    required this.active,
    required this.onTap,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$name, admission $admissionNumber, $statusLabel',
      excludeSemantics: true,
      child: Material(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ParentsAvatar(name: name, photoUrl: photoUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                admissionNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? p.success : p.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: t.bodySmall?.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: p.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An outlined account action with an icon (login-access actions).
class ParentsActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const ParentsActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        foregroundColor: p.primary,
        side: BorderSide(color: p.primary.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
