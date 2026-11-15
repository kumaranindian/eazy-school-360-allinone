import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../authentication/domain/mfa.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../authentication/presentation/sign_out.dart';
import '../providers/platform_session_providers.dart';
import '../widgets/platform_scaffold.dart';

/// Shown to a platform administrator whose session has no second factor.
///
/// * No authenticator app yet: add one (QR code or key, then the first code).
/// * One is enrolled but this session did not use it (the person has just
///   enrolled): sign in again with the code. Firebase only puts the second
///   factor on the token at sign-in, so this is required, not a formality.
class PlatformMfaPage extends ConsumerWidget {
  const PlatformMfaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(sessionSecurityProvider);
    return PlatformScaffold(
      title: 'Two-step verification',
      showBack: false,
      child: PlatformBody(
        maxWidth: 560,
        child: security.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(
            icon: Icons.error_outline,
            title: 'Could not check your sign-in',
            body: userMessageFor(e),
            action: FilledButton(
              onPressed: () => ref.invalidate(sessionSecurityProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (s) =>
              s.enrolledFactors > 0 ? _SignInAgain(ref: ref) : const _Enroll(),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(body, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        Center(child: action),
      ],
    );
  }
}

class _SignInAgain extends StatelessWidget {
  final WidgetRef ref;

  const _SignInAgain({required this.ref});

  @override
  Widget build(BuildContext context) => _Message(
    icon: Icons.verified_user_outlined,
    title: 'Sign in again with your code',
    body:
        'Two-step verification is set up. Sign out, then sign in again and '
        'enter the 6-digit code from your authenticator app.',
    action: FilledButton.icon(
      key: const ValueKey('mfa-sign-out'),
      icon: const Icon(Icons.logout),
      label: const Text('Sign out'),
      onPressed: () => signOutWithCleanup(ref),
    ),
  );
}

class _Enroll extends ConsumerStatefulWidget {
  const _Enroll();

  @override
  ConsumerState<_Enroll> createState() => _EnrollState();
}

class _EnrollState extends ConsumerState<_Enroll> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  late Future<TotpEnrollment> _start = _begin();
  bool _busy = false;
  bool _done = false;
  String? _error;

  Future<TotpEnrollment> _begin() =>
      ref.read(authRepositoryProvider).startTotpEnrollment();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _finish(TotpEnrollment enrollment) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .finishTotpEnrollment(enrollment, _code.text);
      if (!mounted) return;
      ref.invalidate(sessionSecurityProvider);
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userMessageFor(e);
        _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _SignInAgain(ref: ref);
    final text = Theme.of(context).textTheme;
    return FutureBuilder<TotpEnrollment>(
      future: _start,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline,
            title: 'Could not start the setup',
            body: userMessageFor(snap.error!),
            action: FilledButton(
              onPressed: () => setState(() => _start = _begin()),
              child: const Text('Try again'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final e = snap.data!;
        return Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('Protect your account', style: text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Platform administrators must use two-step verification. '
                'Scan this code with an authenticator app (Google '
                'Authenticator, Microsoft Authenticator, 1Password...), then '
                'enter the 6-digit code it shows.',
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: QrImageView(
                    key: const ValueKey('mfa-qr'),
                    data: e.otpAuthUrl,
                    size: 200,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Cannot scan? Enter this key instead:',
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      e.secretKey,
                      key: const ValueKey('mfa-secret'),
                      style: text.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy key',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: e.secretKey));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Key copied')),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('mfa-enroll-code'),
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: '6-digit code from the app',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                validator: validateTotpCode,
                onFieldSubmitted: (_) => _finish(e),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const ValueKey('mfa-enroll-submit'),
                onPressed: _busy ? null : () => _finish(e),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Turn on two-step verification'),
              ),
            ],
          ),
        );
      },
    );
  }
}
