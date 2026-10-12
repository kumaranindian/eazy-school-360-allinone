import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../providers/auth_providers.dart';

class ForgotPasswordForm extends ConsumerStatefulWidget {
  const ForgotPasswordForm({super.key});

  @override
  ConsumerState<ForgotPasswordForm> createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends ConsumerState<ForgotPasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(passwordResetControllerProvider.notifier)
        .sendResetEmail(_emailController.text.trim());

    final state = ref.read(passwordResetControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      context.showSnackBar(userMessageFor(state.error!), isError: true);
    } else {
      setState(() => _emailSent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resetState = ref.watch(passwordResetControllerProvider);
    final isSubmitting = resetState.isLoading;

    if (_emailSent) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 40,
            color: context.colors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            "If an account exists for that email, we've sent a link to reset the password.",
            style: context.textStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.login),
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            enabled: !isSubmitting,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.email,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }
}
