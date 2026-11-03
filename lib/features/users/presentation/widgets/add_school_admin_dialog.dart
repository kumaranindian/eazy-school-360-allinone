import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/login_provisioning.dart';
import '../../domain/school_admin.dart';
import '../providers/school_admin_providers.dart';
import 'password_setup_picker.dart';

/// Adds another school administrator. The server does the work (clients may
/// not grant `SCHOOL_ADMIN`); this dialog collects the person's details and
/// how their first password is set, then — for the activation-email option —
/// sends them the set-password email. Resolves to true when an admin was added.
Future<bool?> showAddSchoolAdminDialog({
  required BuildContext context,
  required String schoolId,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => AddSchoolAdminDialog(schoolId: schoolId),
);

/// The options that make sense for an administrator. "Name + mobile" is left
/// out: it is guessable, and this is the most powerful role in the school.
const _adminOptions = [
  PasswordSetupOption.activationEmail,
  PasswordSetupOption.randomTemp,
  PasswordSetupOption.adminDefined,
];

class AddSchoolAdminDialog extends ConsumerStatefulWidget {
  final String schoolId;
  const AddSchoolAdminDialog({super.key, required this.schoolId});

  @override
  ConsumerState<AddSchoolAdminDialog> createState() =>
      _AddSchoolAdminDialogState();
}

class _AddSchoolAdminDialogState extends ConsumerState<AddSchoolAdminDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  PasswordSetupOption _option = PasswordSetupOption.activationEmail;
  bool _showPassword = false;
  bool _running = false;
  CreatedSchoolAdmin? _created;
  String? _notice;
  String? _error;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canRun =>
      !_running &&
      PasswordSetupPicker.isValid(_option, _password.text, _confirm.text);

  Future<void> _run() async {
    if (!(_form.currentState?.validate() ?? false) || !_canRun) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(schoolAdminRepositoryProvider)
          .create(
            schoolId: widget.schoolId,
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            passwordSetup: PasswordSetup(
              _option,
              password: _option == PasswordSetupOption.adminDefined
                  ? _password.text
                  : null,
            ),
          );
      String notice;
      if (_option.sendsEmail) {
        // The account exists; the email is the person's way in. If sending it
        // fails, say so — the admin can use "Reset password" later.
        try {
          await ref
              .read(authRepositoryProvider)
              .sendPasswordResetEmail(created.email);
          notice =
              '${created.name} is now a school admin. A set-password email '
              'was sent to ${created.email}.';
        } catch (e) {
          notice =
              '${created.name} is now a school admin, but the set-password '
              'email could not be sent (${userMessageFor(e)}). Ask them to '
              'use "Forgot password" on the sign-in page.';
        }
      } else {
        notice =
            '${created.name} is now a school admin and must change the '
            'password at first sign-in.';
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _created = created;
        _notice = notice;
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
    final done = _created != null;
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
                Text('Add school admin', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: done ? _result(theme) : _formBody(theme),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!done)
                        TextButton(
                          onPressed: _running
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      FilledButton(
                        onPressed: done
                            ? () => Navigator.of(context).pop(true)
                            : (_canRun ? _run : null),
                        child: _running
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(done ? 'Done' : 'Add school admin'),
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

  Widget _formBody(ThemeData theme) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A school admin can manage every branch, all staff, students, fees '
          'and settings. Only add people you trust.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          enabled: !_running,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          validator: (v) =>
              (v ?? '').trim().length < 2 ? 'Enter their name.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _email,
          enabled: !_running,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            helperText: 'They sign in with this email.',
          ),
          validator: (v) => _emailPattern.hasMatch((v ?? '').trim())
              ? null
              : 'Enter a valid email address.',
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phone,
          enabled: !_running,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile (optional)'),
        ),
        const SizedBox(height: 16),
        PasswordSetupPicker(
          heading: 'How should their first password be set?',
          options: _adminOptions,
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
    ),
  );

  Widget _result(ThemeData theme) {
    final temp = _created?.tempPassword;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(_notice ?? 'Done.', style: theme.textTheme.titleMedium),
        ),
        if (temp != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Temporary password — shown only now and not saved. Hand it over '
            'securely.',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  temp,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy password',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: temp));
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
}
