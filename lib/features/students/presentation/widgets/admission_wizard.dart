import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Presentation pieces of the admission wizard: a title banner, a horizontal
/// numbered step tracker and the card each step sits in. No data or
/// navigation of their own.

/// The blue title band under the app bar: back arrow, title, subtitle and an
/// optional action (e.g. "Bulk upload").
class AdmissionBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget? action;

  const AdmissionBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, AppSpacing.md, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, color: scheme.onPrimary),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onPrimary.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// "1 ── 2 ── 3 ── 4" with a label under each circle. The current step is
/// filled, finished steps show a check (and can be tapped to go back), later
/// steps are grey. Labels may wrap to two lines and scale with the text size.
class AdmissionStepTracker extends StatelessWidget {
  final List<String> labels;
  final int current;
  final ValueChanged<int>? onTapStep;

  const AdmissionStepTracker({
    super.key,
    required this.labels,
    required this.current,
    this.onTapStep,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final line = scheme.outlineVariant;
    return Semantics(
      container: true,
      label: 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: InkWell(
                onTap: onTapStep != null && i < current
                    ? () => onTapStep!(i)
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: i == 0
                                ? const SizedBox(height: 2)
                                : Container(
                                    height: 2,
                                    color: i <= current ? scheme.primary : line,
                                  ),
                          ),
                          _Dot(
                            number: i + 1,
                            done: i < current,
                            active: i == current,
                          ),
                          Expanded(
                            child: i == labels.length - 1
                                ? const SizedBox(height: 2)
                                : Container(
                                    height: 2,
                                    color: i < current ? scheme.primary : line,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: i <= current
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: i == current
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final int number;
  final bool done;
  final bool active;
  const _Dot({required this.number, required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = done || active;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : scheme.surfaceContainerHighest,
      ),
      child: done
          ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
          : Text(
              '$number',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// The rounded card of one step: a header (icon, title, subtitle), the step's
/// content and the footer buttons.
class AdmissionStepCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  const AdmissionStepCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary),
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
            const SizedBox(height: AppSpacing.md),
            footer,
          ],
        ),
      ),
    );
  }
}

/// Two fields side by side from [breakpoint] wide, stacked below it.
class AdmissionFieldRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double breakpoint;
  const AdmissionFieldRow({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 520,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.sm),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// A field label with an optional red star, above its input.
class AdmissionLabeled extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  const AdmissionLabeled({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              text: label,
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              children: [
                if (required)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: scheme.error),
                  ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
