import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../providers/auth_providers.dart';

class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(signInControllerProvider.notifier)
        .signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    final state = ref.read(signInControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      context.showSnackBar(userMessageFor(state.error!), isError: true);
    }
  }

  Future<void> _submitGoogle() async {
    await ref.read(googleSignInControllerProvider.notifier).signInWithGoogle();

    final state = ref.read(googleSignInControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      context.showSnackBar(userMessageFor(state.error!), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signInState = ref.watch(signInControllerProvider);
    final googleSignInState = ref.watch(googleSignInControllerProvider);
    final isSubmitting = signInState.isLoading || googleSignInState.isLoading;

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
            autofillHints: const [AutofillHints.password],
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
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
            onFieldSubmitted: (_) => _submit(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => context.push(AppRoutes.forgotPassword),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: signInState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Sign in'),
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
            onPressed: isSubmitting ? null : _submitGoogle,
            icon: googleSignInState.isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.g_mobiledata),
            label: const Text('Sign in with Google'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => context.push(AppRoutes.register),
              child: const Text('Register your school'),
            ),
          ),
        ],
      ),
    );
  }
}
