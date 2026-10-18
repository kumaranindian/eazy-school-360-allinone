import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/login_method.dart';
import '../providers/auth_providers.dart';
import '../providers/initial_password_providers.dart';
import '../sign_out.dart';
import '../widgets/auth_scaffold.dart';

/// Shown on first sign-in after an administrator set (or derived) the
/// password. The person picks their own; the old one stops working.
class ChangeInitialPasswordPage extends ConsumerStatefulWidget {
  const ChangeInitialPasswordPage({super.key});

  @override
  ConsumerState<ChangeInitialPasswordPage> createState() =>
      _ChangeInitialPasswordPageState();
}

class _ChangeInitialPasswordPageState
    extends ConsumerState<ChangeInitialPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _skipIfNotPasswordSignIn();
  }

  /// A Google or phone-code session never used the password, so there is
  /// nothing to change here.
  Future<void> _skipIfNotPasswordSignIn() async {
    final method = await ref.read(authRepositoryProvider).currentSignInMethod();
    if (!mounted || method == null || method == LoginMethod.password) return;
    ref.read(initialPasswordGateDismissedProvider.notifier).dismiss();
    if (mounted) context.go(AppRoutes.dashboard);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static String? _policy(String? v) {
    final value = v ?? '';
    if (value.length < AppConstants.minPasswordLength) {
      return 'Use at least ${AppConstants.minPasswordLength} characters.';
    }
    if (!RegExp('[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = ref.read(tenantContextProvider).value?.user.email;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(changeInitialPasswordProvider)(_password.text);
      // The server ends every session when the password changes: sign in again
      // with the new one, then reload the profile (the flag is now cleared).
      if (email != null) {
        await ref
            .read(authRepositoryProvider)
            .signInWithEmailAndPassword(email: email, password: _password.text);
      }
      ref.invalidate(tenantContextProvider);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'Choose your own password',
      subtitle:
          'Your administrator set a temporary password. Pick a new one to '
          'continue — the temporary one will stop working.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _password,
              obscureText: !_show,
              enabled: !_saving,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: _show ? 'Hide password' : 'Show password',
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
              validator: _policy,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirm,
              obscureText: !_show,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (v) =>
                  v == _password.text ? null : 'Passwords do not match.',
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save password'),
            ),
            TextButton(
              onPressed: _saving ? null : () => signOutWithCleanup(ref),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
