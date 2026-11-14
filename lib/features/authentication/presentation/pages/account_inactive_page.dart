import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/support_contact.dart';

import '../../../../core/tenant/account_inactive_exception.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../users/domain/user_status.dart';
import '../sign_out.dart';
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
    if (cause == InactiveCause.schoolPaused) {
      final state = error is AccountInactiveException
          ? error.schoolState
          : null;
      (title, message) = _schoolMessage(state);
    } else if (cause == InactiveCause.invalidProfile) {
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

    final paused = cause == InactiveCause.schoolPaused;
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
          if (paused) ...[
            FilledButton.icon(
              key: const ValueKey('contact-support'),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Contact support'),
              onPressed: () => _contactSupport(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => signOutWithCleanup(ref),
              child: const Text('Sign out'),
            ),
          ] else
            FilledButton(
              onPressed: () => signOutWithCleanup(ref),
              child: const Text('Sign out'),
            ),
        ],
      ),
    );
  }
}

/// The title and message for a school that cannot be used. The support address
/// is a fixed constant ([platformSupportEmail]).
(String, String) _schoolMessage(String? state) => switch (state) {
  'SUSPENDED' => (
    'School account suspended',
    'Your school account has been suspended. Please contact '
        '$platformSupportEmail for assistance.',
  ),
  'SUBSCRIPTION_NOT_STARTED' => (
    'Subscription not started yet',
    'Your school subscription has not started yet. Please contact '
        '$platformSupportEmail.',
  ),
  'SUBSCRIPTION_EXPIRED' || 'EXPIRED' => (
    'School subscription expired',
    'Your school subscription has expired. Please contact '
        '$platformSupportEmail.',
  ),
  'CLOSED' => (
    'School account closed',
    'Your school account has been closed. Please contact '
        '$platformSupportEmail.',
  ),
  _ => (
    'Account is inactive',
    'Account is inactive. Please contact $platformSupportEmail.',
  ),
};

/// Opens the mail app; if that is not possible, copies the address.
Future<void> _contactSupport(BuildContext context) async {
  final ok = await launchUrl(
    Uri(scheme: 'mailto', path: platformSupportEmail),
  ).catchError((_) => false);
  if (!ok) {
    await Clipboard.setData(const ClipboardData(text: platformSupportEmail));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support address copied.')));
    }
  }
}
