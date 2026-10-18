import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/login_provisioning.dart';
import '../providers/login_access_providers.dart';
import 'password_setup_picker.dart';

/// Lets an administrator set a new password for someone who already has a
/// login, with the same choices as when the login was created. The link
/// options send the person a set-password email; the others set the password
/// on the server and make them change it at next sign-in (all their sessions
/// are signed out). A password typed or generated here is sent once and never
/// stored. Resolves to true when something was done.
Future<bool?> showResetPasswordDialog({
  required BuildContext context,
  required String schoolId,
  required String branchId,
  required LoginKind kind,
  required String id,
  required String name,
  required String? email,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ResetPasswordDialog(
    schoolId: schoolId,
    branchId: branchId,
    kind: kind,
    id: id,
    name: name,
    email: email,
  ),
);

class ResetPasswordDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final LoginKind kind;
  final String id;
  final String name;
  final String? email;

  const ResetPasswordDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.id,
    required this.name,
    required this.email,
  });

  @override
  ConsumerState<ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<ResetPasswordDialog> {
  PasswordSetupOption _option = PasswordSetupOption.activationEmail;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _running = false;
  bool _done = false;
  String? _error;
  String? _notice;
  String? _tempPassword;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasEmail => (widget.email ?? '').trim().isNotEmpty;
  bool get _needsEmail => _option.sendsEmail && !_hasEmail;
  bool get _canRun =>
      !_running &&
      !_needsEmail &&
      PasswordSetupPicker.isValid(_option, _password.text, _confirm.text);

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      if (_option.sendsEmail) {
        await ref
            .read(authRepositoryProvider)
            .sendPasswordResetEmail(widget.email!.trim());
        _notice = 'A set-password email was sent to ${widget.email!.trim()}.';
      } else {
        _tempPassword = await ref
            .read(loginAccessRepositoryProvider)
            .resetPassword(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              kind: widget.kind,
              id: widget.id,
              passwordSetup: PasswordSetup(
                _option,
                password: _option == PasswordSetupOption.adminDefined
                    ? _password.text
                    : null,
              ),
            );
        _notice =
            '${widget.name} was signed out of every device and must change '
            'the password at next sign-in.';
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = userMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_running,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reset password', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: _done ? _result(theme) : _form(theme),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_done)
                        TextButton(
                          onPressed: _running
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      FilledButton(
                        onPressed: _done
                            ? () => Navigator.of(context).pop(true)
                            : _canRun
                            ? _run
                            : null,
                        child: _running
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _done
                                    ? 'Done'
                                    : _option.sendsEmail
                                    ? 'Send email'
                                    : 'Reset password',
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Set a new password for ${widget.name}. Choose how, the same as when '
        'logins are created.',
      ),
      const SizedBox(height: 12),
      PasswordSetupPicker(
        heading: 'How should the new password be set?',
        option: _option,
        onOptionChanged: (v) => setState(() => _option = v),
        password: _password,
        confirm: _confirm,
        showPassword: _showPassword,
        onToggleShowPassword: () =>
            setState(() => _showPassword = !_showPassword),
        onChanged: () => setState(() {}),
        enabled: !_running,
      ),
      if (_needsEmail)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'There is no email on the record, so a link cannot be sent. '
            'Choose another option.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
    ],
  );

  Widget _result(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(_notice ?? 'Done.', style: theme.textTheme.titleMedium),
      ),
      if (_tempPassword != null) ...[
        const SizedBox(height: 12),
        Text(
          'Temporary password — shown only now and not saved. Hand it over '
          'securely.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                _tempPassword!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy password',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _tempPassword!));
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Copied')));
                }
              },
            ),
          ],
        ),
      ],
    ],
  );
}
