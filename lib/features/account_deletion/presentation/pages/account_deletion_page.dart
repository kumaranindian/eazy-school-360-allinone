import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../authentication/domain/google_sign_in_cancelled.dart';
import '../../../authentication/domain/login_method.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/account_deletion_repository.dart';
import '../../domain/deletion_copy.dart';
import '../../domain/deletion_request.dart';
import '../providers/account_deletion_providers.dart';

const _privacyUrl = 'https://eazyschool.avail404.com/privacy';
const _webFormUrl = 'https://eazyschool.avail404.com/delete-account';

String _messageFor(Object error) =>
    error is DeletionFailure ? error.message : userMessageFor(error);

/// Settings -> Delete account. Files a deletion REQUEST; nothing is deleted
/// here. Avail404 reviews every request, and the screen keeps saying so until
/// the server reports it completed.
class AccountDeletionPage extends ConsumerStatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  ConsumerState<AccountDeletionPage> createState() =>
      _AccountDeletionPageState();
}

class _AccountDeletionPageState extends ConsumerState<AccountDeletionPage> {
  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    if (_busy) return; // one request at a time, however fast the taps
    final understood = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(),
    );
    if (understood != true || !mounted) return;

    final method = await ref.read(authRepositoryProvider).currentSignInMethod();
    if (!mounted) return;
    final confirmed = await showAdaptiveAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReauthDialog(method: method ?? LoginMethod.password),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final created = await ref
          .read(accountDeletionControllerProvider.notifier)
          .submit();
      _snack('Request received. Your reference is ${created.reference}.');
    } catch (e) {
      _snack(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(DeletionRequest request) async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text(
          'Your account stays as it is and nothing is deleted. You can '
          'request deletion again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(accountDeletionControllerProvider.notifier)
          .cancel(request.reference);
      _snack('Request cancelled. Nothing was deleted.');
    } catch (e) {
      _snack(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Could not open the link.');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountDeletionControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.dashboard),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AsyncValueWidget<List<DeletionRequest>>(
              value: state,
              errorMessage: _messageFor,
              onRetry: () => ref.invalidate(accountDeletionControllerProvider),
              data: _content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(List<DeletionRequest> requests) {
    final theme = Theme.of(context);
    final latest = requests.isEmpty ? null : requests.first;
    final open = latest != null && latest.status.isOpen;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Ask Avail404 to delete your EazySchool 360 account and personal '
          'data. This sends a request; nothing is deleted straight away.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (latest != null) ...[
          _RequestCard(
            request: latest,
            busy: _busy,
            onCancel: latest.status.canCancel ? () => _cancel(latest) : null,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        _Bullets(title: 'What we delete', items: DeletionCopy.deleted),
        const SizedBox(height: AppSpacing.md),
        _Bullets(title: 'What we may keep, and why', items: DeletionCopy.kept),
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'If you run a school',
          child: const Text(
            'Deleting your account does not close the school. If you are the '
            'only administrator, we cannot finish the request until another '
            'administrator is added, so the school is not left without '
            'anyone able to manage it.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'What happens next',
          child: const Text(
            'You confirm it is you, then Avail404 reviews the request and '
            'aims to finish within ${DeletionCopy.reviewTarget}. You can '
            'check progress here, and cancel before it is approved. Once '
            'deleted, it cannot be undone.',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!open)
          FilledButton.icon(
            key: const Key('request-deletion'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: _busy ? null : _start,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: const Text('Request account deletion'),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: () => _open(_privacyUrl),
              child: const Text('Privacy policy'),
            ),
            TextButton(
              onPressed: () => _open(_webFormUrl),
              child: const Text('Request without the app'),
            ),
          ],
        ),
        Text('Questions: hi@avail404.com', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        DefaultTextStyle.merge(style: theme.textTheme.bodyMedium, child: child),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  final String title;
  final List<String> items;
  const _Bullets({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final DeletionRequest request;
  final bool busy;
  final VoidCallback? onCancel;
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = DeletionCopy.forRequest(request);
    return Card(
      key: const Key('request-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(copy.title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(copy.body),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    'Reference: ${request.reference}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy reference',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: request.reference),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reference copied')),
                      );
                    }
                  },
                ),
              ],
            ),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: const Key('cancel-request'),
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel request'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog();

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delete your account?', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'This asks Avail404 to delete your account and personal data. '
          'After the request is approved and carried out, it cannot be '
          'undone. Records your school or the law requires us to keep are '
          'not deleted.',
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          key: const Key('understood'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: (v) => setState(() => _understood = v ?? false),
          title: const Text('I understand and want to request deletion'),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const Key('confirm-understood'),
              onPressed: _understood
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Confirm it is you": the server only accepts a request from a sign-in made
/// minutes ago, so the person proves themselves again the way they sign in.
class _ReauthDialog extends ConsumerStatefulWidget {
  final LoginMethod method;
  const _ReauthDialog({required this.method});

  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _input = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;
  String? _challengeId; // phone: set once the code has been sent

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await action();
      if (done && mounted) Navigator.pop(context, true);
    } on GoogleSignInCancelled {
      // The person closed the Google picker: stay on this dialog.
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _password() async {
    await ref.read(reauthenticatorProvider).withPassword(_input.text);
    return true;
  }

  Future<bool> _google() async {
    await ref.read(reauthenticatorProvider).withGoogle();
    return true;
  }

  Future<bool> _sendCode(String phone) async {
    final challenge = await ref
        .read(authRepositoryProvider)
        .requestPhoneOtp(phone);
    if (mounted) setState(() => _challengeId = challenge.challengeId);
    return false; // stay open for the code
  }

  Future<bool> _verifyCode() async {
    await ref
        .read(authRepositoryProvider)
        .verifyPhoneOtp(challengeId: _challengeId!, code: _input.text);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only the phone-code path needs the profile; the others must not touch it.
    final phone = widget.method == LoginMethod.phoneOtp
        ? ref.watch(tenantContextProvider).value?.user.phone
        : null;
    final children = <Widget>[];

    switch (widget.method) {
      case LoginMethod.password:
        children.addAll([
          const Text('Enter your password to confirm it is you.'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('reauth-password'),
            controller: _input,
            obscureText: !_show,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide password' : 'Show password',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            onSubmitted: (_) => _run(_password),
          ),
        ]);
      case LoginMethod.google:
        children.add(const Text('Confirm it is you with your Google account.'));
      case LoginMethod.phoneOtp:
        if (phone == null || phone.isEmpty) {
          children.add(
            const Text(
              'There is no phone number on your account to send a code to. '
              'Sign out, sign in again, and then request deletion straight '
              'away, or email hi@avail404.com.',
            ),
          );
        } else if (_challengeId == null) {
          children.add(
            const Text(
              'We will send a one-time code by WhatsApp to the phone number '
              'on your account.',
            ),
          );
        } else {
          children.addAll([
            const Text('Enter the code we sent you on WhatsApp.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('reauth-code'),
              controller: _input,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'Code'),
              onSubmitted: (_) => _run(_verifyCode),
            ),
          ]);
        }
    }

    if (_error != null) {
      children.addAll([
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ]);
    }

    final VoidCallback? action = _busy
        ? null
        : switch (widget.method) {
            LoginMethod.password => () => _run(_password),
            LoginMethod.google => () => _run(_google),
            LoginMethod.phoneOtp =>
              (phone == null || phone.isEmpty)
                  ? null
                  : _challengeId == null
                  ? () => _run(() => _sendCode(phone))
                  : () => _run(_verifyCode),
          };
    final label = switch (widget.method) {
      LoginMethod.password => 'Confirm',
      LoginMethod.google => 'Continue with Google',
      LoginMethod.phoneOtp => _challengeId == null ? 'Send code' : 'Confirm',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Confirm it is you', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        ...children,
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('reauth-confirm'),
              onPressed: action,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ),
      ],
    );
  }
}
