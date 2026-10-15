import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/account_inactive_exception.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../users/domain/user_status.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_scaffold.dart';

/// Shown when the signed-in user's profile is not ACTIVE. The account is
/// still authenticated with Firebase, but `firestore.rules` denies it all
/// tenant data, so signing out is the only action offered.
class AccountInactivePage extends ConsumerWidget {
  const AccountInactivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(tenantContextProvider).error;
    final cause = error is AccountInactiveException
        ? error.cause
        : InactiveCause.status;
    final isInvited =
        error is AccountInactiveException &&
        cause == InactiveCause.status &&
        error.status == UserStatus.invited;

    final String title;
    final String message;
    if (cause == InactiveCause.invalidProfile) {
      title = "Your account isn't set up correctly";
      message =
          'Your profile is missing a valid role. Ask your school administrator '
          'to check your account.';
    } else if (cause == InactiveCause.loginDisabled) {
      title = 'Login access is turned off';
      message =
          'Your school administrator has turned off login for your account. '
          'Contact them if you believe this is a mistake.';
    } else if (cause == InactiveCause.methodNotPermitted) {
      final permitted = (error as AccountInactiveException).permitted;
      title = "This sign-in method isn't allowed";
      message = permitted.isEmpty
          ? 'None of the sign-in methods are currently allowed for your account. '
                'Contact your school administrator.'
          : 'Sign out and use: ${permitted.map((m) => m.label).join(', ')}.';
    } else if (isInvited) {
      title = "Your account isn't active yet";
      message =
          'Your school administrator has invited you, but your account has not been activated yet.';
    } else {
      title = 'Your account has been disabled';
      message =
          'Contact your school administrator if you believe this is a mistake.';
    }

    return AuthScaffold(
      title: title,
      subtitle: message,
      formWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isInvited ? Icons.hourglass_empty : Icons.block,
            size: 48,
            color: isInvited
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
