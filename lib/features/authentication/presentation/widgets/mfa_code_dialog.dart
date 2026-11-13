import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/mfa.dart';
import '../providers/auth_providers.dart';

/// Asks for the 6-digit code from the authenticator app after a correct
/// password. Closes itself when the code is accepted (the router then moves on
/// because the auth state changed); a wrong code is explained and can be
/// retyped.
class MfaCodeDialog extends ConsumerStatefulWidget {
  final MfaPending pending;

  const MfaCodeDialog({super.key, required this.pending});

  static Future<void> show(BuildContext context, MfaPending pending) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MfaCodeDialog(pending: pending),
      );

  @override
  ConsumerState<MfaCodeDialog> createState() => _MfaCodeDialogState();
}

class _MfaCodeDialogState extends ConsumerState<MfaCodeDialog> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final ok = await ref
        .read(mfaSignInControllerProvider.notifier)
        .complete(widget.pending, _code.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _error = userMessageFor(ref.read(mfaSignInControllerProvider).error!);
        _code.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(mfaSignInControllerProvider).isLoading;
    return AlertDialog(
      title: const Text('Two-step verification'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open your authenticator app and enter the 6-digit code for '
              'EazySchool 360.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('mfa-code'),
              controller: _code,
              autofocus: true,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(
                labelText: '6-digit code',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              validator: validateTotpCode,
              onFieldSubmitted: (_) => _verify(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _verify,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}
