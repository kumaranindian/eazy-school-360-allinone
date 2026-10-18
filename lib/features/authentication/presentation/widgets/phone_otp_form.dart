import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/phone_otp.dart';
import '../providers/auth_providers.dart';

/// Phone sign-in: enter the registered mobile, then the 6-digit code sent by
/// WhatsApp. Signing in happens only after the server accepts the code; the
/// router then takes over exactly as for any other method.
class PhoneOtpForm extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const PhoneOtpForm({super.key, required this.onBack});

  @override
  ConsumerState<PhoneOtpForm> createState() => _PhoneOtpFormState();
}

class _PhoneOtpFormState extends ConsumerState<PhoneOtpForm> {
  final _phoneKey = GlobalKey<FormState>();
  final _codeKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_phoneKey.currentState?.validate() ?? false)) return;
    await ref
        .read(phoneOtpControllerProvider.notifier)
        .requestCode(_phone.text.trim());
  }

  Future<void> _verify() async {
    if (!(_codeKey.currentState?.validate() ?? false)) return;
    await ref.read(phoneOtpControllerProvider.notifier).verify(_code.text);
    if (mounted) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(phoneOtpControllerProvider);
    final theme = Theme.of(context);
    final wait = s.resendAt == null
        ? 0
        : s.resendAt!.difference(DateTime.now()).inSeconds.clamp(0, 3600);

    final error = s.error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                s.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          );
    final spinner = const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );

    if (s.step == OtpStep.enterPhone) {
      return Form(
        key: _phoneKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'We will send a one-time code by WhatsApp to the mobile number '
              'registered with your school.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phone,
              enabled: !s.busy,
              autofillHints: const [AutofillHints.telephoneNumber],
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Registered mobile number',
                helperText: 'Include your country code, e.g. +971 50 123 4567',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: validatePhoneNumber,
              onFieldSubmitted: (_) => _send(),
            ),
            if (error != null) error,
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: s.busy ? null : _send,
              child: s.busy ? spinner : const Text('Send code'),
            ),
            TextButton(
              onPressed: s.busy ? null : widget.onBack,
              child: const Text('Use email instead'),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _codeKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the 6-digit code we sent to ${s.phone} on WhatsApp.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _code,
            enabled: !s.busy,
            autofillHints: const [AutofillHints.oneTimeCode],
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Verification code',
              prefixIcon: Icon(Icons.pin_outlined),
              counterText: '',
            ),
            validator: validateOtpCode,
            onFieldSubmitted: (_) => _verify(),
          ),
          if (error != null) error,
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: s.busy ? null : _verify,
            child: s.busy ? spinner : const Text('Verify and sign in'),
          ),
          TextButton(
            onPressed: s.busy || wait > 0
                ? null
                : () => ref
                      .read(phoneOtpControllerProvider.notifier)
                      .requestCode(s.phone),
            child: Text(wait > 0 ? 'Resend code in ${wait}s' : 'Resend code'),
          ),
          TextButton(
            onPressed: s.busy
                ? null
                : ref.read(phoneOtpControllerProvider.notifier).changeNumber,
            child: const Text('Use a different number'),
          ),
        ],
      ),
    );
  }
}
