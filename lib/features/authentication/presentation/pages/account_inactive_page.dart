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
    final isInvited =
        error is AccountInactiveException && error.status == UserStatus.invited;

    final title = isInvited
        ? "Your account isn't active yet"
        : 'Your account has been disabled';
    final message = isInvited
        ? 'Your school administrator has invited you, but your account has not been activated yet.'
        : 'Contact your school administrator if you believe this is a mistake.';

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
