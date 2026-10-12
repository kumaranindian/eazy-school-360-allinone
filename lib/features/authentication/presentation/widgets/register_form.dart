import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../providers/auth_providers.dart';

class RegisterForm extends ConsumerStatefulWidget {
  const RegisterForm({super.key});

  @override
  ConsumerState<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(signUpControllerProvider.notifier)
        .signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    final state = ref.read(signUpControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      context.showSnackBar(userMessageFor(state.error!), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signUpState = ref.watch(signUpControllerProvider);
    final isSubmitting = signUpState.isLoading;

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
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.email,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _passwordController,
            enabled: !isSubmitting,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: Validators.password,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirmPasswordController,
            enabled: !isSubmitting,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
              ),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return Validators.required(value, fieldName: 'Confirm password');
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: signUpState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Create account'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('or', style: Theme.of(context).textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isSubmitting
                ? null
                : () => ref
                      .read(googleSignInControllerProvider.notifier)
                      .signInWithGoogle(),
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Sign up with Google'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => context.push(AppRoutes.login),
              child: const Text('Already have an account? Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}
