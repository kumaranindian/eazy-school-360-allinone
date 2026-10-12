import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/branding/brand_logo.dart';
import '../../../../shared/widgets/app_version_footer.dart';

/// The shared frame for every signed-out screen (sign in, register, reset
/// password, inactive account), so they all carry the brand the same way.
///
/// Wide windows get a two-pane layout: a navy brand panel on the left and
/// the form on the right. Narrow ones get the logo over a single card. The
/// form column scrolls, so it stays usable with the keyboard open.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  /// Maximum width of the form card.
  final double formWidth;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.formWidth = 440,
  });

  static const double _splitBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: formWidth),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      bottomNavigationBar: const SafeArea(child: AppVersionFooter()),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= _splitBreakpoint;
          if (split) {
            return Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 4,
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: form,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(height: 64),
                    const SizedBox(height: AppSpacing.lg),
                    form,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The dark lockup carries its own navy backdrop, so it is shown
              // as a deliberate badge rather than blended into the gradient.
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.antiAlias,
                child: const BrandLogo(height: 120, onDark: true),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Run your whole school from one place.',
                style: text.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final line in const [
                'Admissions, attendance and timetables',
                'Fees, invoices and receipts',
                'Homework, exams and results',
                'Staff, leave and parent communication',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          line,
                          style: text.bodyLarge?.copyWith(
                            color: const Color(0xFFD9EAFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
