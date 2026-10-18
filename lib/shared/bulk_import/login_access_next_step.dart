import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';

/// Shown after a bulk import: logins are optional and are created from the
/// list (select people → "Give login access"), where the admin chooses how
/// each person's first password is set. Importing never creates a login, so
/// a "No" choice needs no action.
class LoginAccessNextStep extends StatelessWidget {
  final String message;
  final String buttonLabel;
  final String route;

  const LoginAccessNextStep({
    super.key,
    required this.message,
    required this.buttonLabel,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Login accounts (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(message),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.go(route),
                icon: const Icon(Icons.key_outlined),
                label: Text(buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
